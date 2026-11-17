# Module template (MIT)

| File | What it is |
|---|---|
| `src/QModuleBase.sol` | The base every marketplace module inherits, **unchanged**. Review checks its SHA-256 against `SHA256SUMS.txt`. |
| `src/QStakeModule.sol` | Reference module: holder staking with fixed-end 24–30-hour reward streams. |
| `src/QRafflePot.sol` | Reference module: a raffle pot with a 1% bounty for timely completed draws. |

Build with [Foundry](https://book.getfoundry.sh): `forge build` (settings in `foundry.toml`: solc 0.8.26, `via_ir`, optimizer 200
runs, `cancun`, `bytecode_hash = none`).

Constructor `(address token, address quote, address builder, uint16 builderBps)`, `builderBps` ≤ 1000 (10%). Deployment:
deterministic deployer `0x4e59b44847b379578588920ca78fbf26c0b4956c`, salt `keccak256("qhooks.module.v1")`,
`init = creationCode ++ abi.encode(token, quote, builder, builderBps)`.

Start with [`../docs/modules.md`](../docs/modules.md), then submit at <https://qhooks.com/market-submit.html>.

## Raffle randomness and expiry

`QRafflePot` uses a future blockhash, not VRF. Block producers or sequencers can predict or influence the result: keep pots small; VRF is planned for a future version. Anyone completing a timely draw earns 1% of each pot currency; the winner receives the remainder. If the draw hash expires after its 256-block window, the round closes without a winner and its pot carries to the next entered round. The expired round cannot be re-armed; entrants can still withdraw their deposits.

## Tests

From the repository root, initialize the pinned test dependency, then run the local mock-only regressions:

```sh
git submodule update --init --recursive
cd contracts
forge test
```

`forge-std` is pinned to v1.9.7 (`77041d2ce690e692d6e03cc812b57d1ddaa4d505`). Tests cover raffle expiry/carry-over/bounties, fixed-end staking streams, dust-sync resistance, just-in-time staking and reward conservation. They require no RPC or wallet.
