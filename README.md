# QHooks builder kit

QHooks is an ecosystem for token builders on Uniswap v4: pick or build the hooks a token trades through, launch it, trade
it in one terminal, let holders stake, protect creator actions with a second post-quantum key, and integrate it all into
your own app. Live at [qhooks.com](https://qhooks.com).

This repository is the public toolkit for builders:

| Path | What it is |
|---|---|
| [`sdk/qhooks.mjs`](sdk/qhooks.mjs) | The QHooks JavaScript SDK: one ES module, no dependencies, no build step. Read launches, pools, trades and holders; quote through a launch's hook; build swap transactions your users sign in their own wallets. The same file is served at `https://qhooks.com/sdk/qhooks.mjs`. |
| [`docs/api.md`](docs/api.md) | The free public read API (`https://qhooks.com/api/v1`): endpoints, SDK functions, limits. |
| [`docs/modules.md`](docs/modules.md) | How builder-marketplace modules work, what review checks, and how to submit one. |
| [`contracts/`](contracts) | The module template (MIT): `QModuleBase` plus the staking and raffle reference modules, with checksums and build settings. |
| [`examples/`](examples) | Small runnable examples. |
| [`ROADMAP.md`](ROADMAP.md) | What we plan to build next. |

The SDK never holds keys or sends transactions. It returns `{ to, data, value }` for the user's wallet to review and send.

## Quick start

```js
import { createClient, withSlippage } from 'https://qhooks.com/sdk/qhooks.mjs';

const q = createClient({ rpc: { '8453': 'https://mainnet.base.org' } });
const pools = await q.pools({ chain: '8453' });
```

See [`examples/quote.mjs`](examples/quote.mjs) for a full quote-and-build-transaction example.

## Links

- Site: <https://qhooks.com> · Developers: <https://qhooks.com/api.html> · Builders: <https://qhooks.com/builders.html>
- Changelog: <https://qhooks.com/changelog.html> · Roadmap: <https://qhooks.com/roadmap.html>
- Telegram: [@qhooks_bot](https://t.me/qhooks_bot) · X: [@qHooks_](https://x.com/qHooks_)

## License

MIT, see [LICENSE](LICENSE). The QHooks name and logo are not covered by the license.
