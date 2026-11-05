# QHooks public API and SDK

Read every listed launch, pool, quote, trade and holder from a free public API. Use the SDK to quote through a launch’s hook and build swap transactions your users sign in their own wallets. No key, no account, no payment.

## Quick start

Base URL `https://qhooks.com/api/v1`. Every endpoint is GET, returns JSON with "version": 1, and allows any origin (CORS).

```
curl https://qhooks.com/api/v1/pools?chain=8453
```

```
import { createClient, withSlippage } from 'https://qhooks.com/sdk/qhooks.mjs';

const q = createClient({ rpc: { '8453': 'https://mainnet.base.org' } });
const [pool] = await q.pools({ chain: '8453' });
const buy = pool.key.currency0 === pool.quote.address;          // quote token → launch token
const { amountOut } = await q.quote({ pool, zeroForOne: buy, amountIn: 20_000000n, trader: me });
const tx = q.universalRouterSwap({ pool, zeroForOne: buy, amountIn: 20_000000n, minOut: withSlippage(amountOut, 100) });
// send tx ({ to, data, value }) from the user's wallet after the Permit2 approvals
```

## Endpoints

| Endpoint | Returns |
|---|---|
| `/chains` | Each chain’s Uniswap v4 PoolManager, StateView, V4Quoter, Universal Router and Permit2, the launch quote token, and QHooks’ shared contracts. feeRouterDeployed says whether QFeeRouter exists there yet. |
| `/markets?chain=` | Listed launches: chain, controller, token, name and symbol, launch time, rules, 24-hour summary (price, volume, trades, holders, market cap). |
| `/markets/{chainId}/{controller}` | One launch: metadata, pools, summary, index sync state and its router profile. |
| `/markets/{chainId}/{controller}/trades` | The latest 100 swaps: block, time, buy or sell, token and quote amounts, price, trader (the wallet, not the router), transaction. |
| `/markets/{chainId}/{controller}/holders` | Top 25 holders and top 25 traders by volume. |
| `/markets/{chainId}/{controller}/candles?tf=` | OHLCV candles; tf in seconds: 60, 300, 900, 3600, 14400 or 86400. |
| `/pools?chain=` | Every initialised pool of every listed launch, with its full v4 PoolKey, hook kind and decoded permission flags, LP fee, protocol fee, current price, quoter and router profile. |
| `/hooks/{chainId}/{hook}` | Any v4 hook address: whether code is deployed, its permission flags, and, for QHooks hooks, the pools that use it. Also the live evidence, plain-language capabilities, shared code, project and Tape activity; see [discover.md](discover.md). |
| `/hooks`, `/hooks/compare`, `/hooks/families/{fp}`, `/hooks/projects[/{id}]`, `/hooks/tape/*` | QHooks Discover: the hook board, comparisons, runtime families, the project registry and the Hook Tape. See [discover.md](discover.md). |
| `/quote?chain=&pool=&zeroForOne=&amountIn=&trader=` | An exact-input quote for a listed pool, simulated on the V4Quoter with from = trader. Includes the LP fee, hook charges and protocol fee. A refused quote returns 422 with the hook’s reason. |
| `/wallets/{address}` | A wallet’s positions across listed launches: balance, bought, sold, spent, received, price. |

Builder-marketplace modules: https://qhooks.com/market/modules.json. Launch alerts: the Telegram bot.

## JavaScript SDK

One ES module, no dependencies and no build step: https://qhooks.com/sdk/qhooks.mjs. It runs in browsers, Node 18+, Deno, Bun and Workers. It never holds keys or sends transactions; it returns { to, data, value } for the user’s wallet.

| Function | What it does |
|---|---|
| `createClient({ api, rpc })` | A client. rpc maps chain IDs to RPC URLs; quotes then run on your own node. |
| `chains() markets() market() trades() holders() candles() pools() hook() wallet() modules()` | The endpoints above. |
| `quote({ pool, zeroForOne, amountIn, trader })` | Exact-input quote through the hook, as the real trader. |
| `universalRouterSwap({ pool, zeroForOne, amountIn, minOut })` | A direct v4 swap through Uniswap’s Universal Router, with no QHooks router fee. ERC-20 input needs approve(token, PERMIT2) and permit2Approve(token, router) first. |
| `prepareFeeRouterSwap({ pool, zeroForOne, amountIn, minOut, feeOnInput, referrer })` | A swap through QFeeRouter, the router the QHooks terminal uses (1% fee, trader cashback, referral credit). Refuses while the router is not deployed on that chain; feeRouterStatus(chainId).setup is the one-time transaction that creates it. |
| `withSlippage(amount, bps), approve(), permit2Approve(), encode()` | Helpers. |

## Routers and aggregators

QHooks launches trade on ordinary Uniswap v4 pools. Any v4 router can reach them with the pool’s PoolKey from /pools. Before routing, know these behaviours.

### The launch hook

Kind qhooks-launch-blocks, permission flags 10956: beforeInitialize, beforeAddLiquidity, beforeRemoveLiquidity, beforeSwap, afterSwap, beforeSwapReturnDelta, afterSwapReturnDelta. Liquidity belongs to the launch; outside liquidity is not accepted. The hook is not upgradeable.

- Charges come through return deltas. A launch’s taxes and other charges, plus a protocol fee (one fifth of the creator’s LP fee), are taken inside the swap. Off-chain constant-product math is not enough: quote with the V4Quoter or a full simulation. The /quote endpoint and the SDK do this.

- Launch windows. In a launch’s first minutes, its rules can refuse a swap: a per-block buy cap, a per-wallet cooldown and wallet cap, a holder gate, an opening bell or an opening auction. router.routable is false until router.routableFrom, and the notes name each rule and when it ends.

- Per-wallet rules use tx.origin. When an EOA sends the swap, the rules apply to that wallet even through a router. Through relayers, solvers or ERC-4337 bundlers, they apply to the relayer. Simulate with from set to the trader. Launches with an exit clock (router.quoteWithTrader) charge sells by how recently that wallet bought.

- Price-path charges. Sandwich, impact and storm charges depend on the price before and after the swap within the block (router.dynamicFee).

- Hook data. Empty hook data is fine. Launches with referrals accept a 32-byte referrer address.

- Indexers. v4’s Swap event is emitted before the hook’s afterSwap, so event-only indexers see prices and volumes without the hook charges.

### The ETH second pool

Kind qhooks-pair: a token/ETH pool some launches open on USDC chains. Same rules and charges, paid in the token. Exact-input swaps only.

## Lab deployments

Hooks deployed from the Lab each get a share page whose link carries a qhooks-hook-deployment manifest. It holds chain, addresses, configuration, build hash and the deployed code hashes. The page re-checks the manifest against the chain, and other tools can register it.

## Limits and notes

- Responses are cached for a few seconds at the edge. Please poll no faster than every 5 seconds per endpoint.

- Only launches listed on Markets appear. Quotes are served only for their pools.

- There are no webhooks yet; poll /markets or use the Telegram bot for alerts.

- Hook inspections (inspector) are read-only, and paid inspection is switched off.

- Contracts are not independently audited. Nothing here is investment advice.
