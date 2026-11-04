# Module template (MIT)

| File | What it is |
|---|---|
| `src/QModuleBase.sol` | The base every marketplace module inherits, **unchanged**. Review checks its SHA-256 against `SHA256SUMS.txt`. |
| `src/QStakeModule.sol` | Reference module: holder staking, payouts streamed over a day. |
| `src/QRafflePot.sol` | Reference module: a raffle pot. |

Build with [Foundry](https://book.getfoundry.sh): `forge build` (settings in `foundry.toml`: solc 0.8.26, `via_ir`, optimizer 200
runs, `cancun`, `bytecode_hash = none`).

Constructor `(address token, address quote, address builder, uint16 builderBps)`, `builderBps` ≤ 1000 (10%). Deployment:
deterministic deployer `0x4e59b44847b379578588920ca78fbf26c0b4956c`, salt `keccak256("qhooks.module.v1")`,
`init = creationCode ++ abi.encode(token, quote, builder, builderBps)`.

Start with [`../docs/modules.md`](../docs/modules.md), then submit at <https://qhooks.com/market-submit.html>.
