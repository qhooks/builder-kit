# QHooks Discover API

Discover covers every Uniswap v4 hook we can see across chains, with the evidence behind each fact: what the hook's address permits, what its deployed code is, which other hooks share that code, which projects stand behind it, and what it did on chain recently. The site is at <https://qhooks.com/discover>. These routes are part of the free public API (`https://qhooks.com/api/v1`): GET, JSON, `"version": 1`, any origin, no key.

## Where each fact comes from

| Fact | Source |
|---|---|
| Hook list, pool and swap counts | A dated snapshot of the v4.xyz community index. The index is not exhaustive, so `coverage.exhaustive` is `false`. Each response carries `snapshotAt`. |
| Hooks marked `source: "tape"` | First-party data: the hook was first seen when a pool was initialised on the official PoolManager. The board is never older than the Tape's finalized head. |
| Code size, SHA-256 runtime fingerprint, permission bits, `owner()` | Read live from the chain at a stated block (`evidence.block`, `observedAt`). |
| Shared code | Hooks whose deployed runtime has the same SHA-256 fingerprint. A shared fingerprint doesn't prove affiliation. |
| Hook Tape | PoolManager `Initialize` and `Swap` logs on Base and Robinhood Chain, from finalized blocks only. |

Fee attribution isn't measured. The swap fee in Tape rows is the LP fee the PoolManager emitted. It doesn't show what a hook earned. A failed read returns `status: "unavailable"` and a reason, never a made-up zero. Anything not built yet is listed under `planned`.

## Endpoints

| Endpoint | Returns |
|---|---|
| `/hooks?chain=&q=&permission=&project=&qhooks=1&new=1&family=&sort=swaps\|pools\|name&limit=&offset=` | The hook board: a page of hooks (limit ≤ 200), each with chain, address, name, counts, permission flags, plain-language `capabilities`, project, runtime family and its profile URL. `new=1` lists only the hooks the Tape found that the snapshot doesn't have. |
| `/hooks/{chainId}/{address}` | One hook. It keeps the original fields (`deployed`, `flags`, `permissions`, `qhooks`, `kind`, `pools`) and adds `evidence` (block, code size, fingerprint, owner probe), `capabilities`, `family`, `board`, `project`, `tape`, `trade` (links into the QHooks terminal), `buildLike` (the closest QHooks Lab templates, launch blocks or modules), `trust` (QHooks launches only), and `measured` / `planned`. Live chains: 8453, 4663, 1, 42161, 56. |
| `/hooks/compare?ids=<chainId>_<address>,…` | Two to four hooks side by side, with `shared` and `differs`. |
| `/hooks/families/{fingerprint}` | Every deployment that shares one runtime. |
| `/hooks/projects?category=` | The project registry. QHooks entries come first: the launch hook, Lab templates and marketplace modules. Each project lists its sources and deployments. |
| `/hooks/projects/{id}` | One project, with a live observation of each deployment (up to 8 per request). |
| `/hooks/tape/status?chain=` | Tape coverage: finalized head, cursors, lag, counts, and the source used. |
| `/hooks/tape/pools?chain=&hook=&limit=&cursor=` | Pool initialisations, newest first. `cursor` is `<block>:<logIndex>`. |
| `/hooks/tape/swaps?chain=&hook=&pool=&limit=&cursor=` | Finalized swaps. Amounts are signed raw pool deltas. |
| `/hooks/tape/activity?chain=&blocks=&hook=` | Swap, pool and sender counts per hook over an explicit block window. |

`POST /api/v1/rpc` takes JSON-RPC 2.0 requests: one request per call (no batches), up to 32 KiB. The methods are `qhooks_chains`, `qhooks_decodePermissions`, `qhooks_chainStatus` and `qhooks_getHook`.

## SDK

```js
import { createClient } from 'https://qhooks.com/sdk/qhooks.mjs';

const q = createClient();
const board = await q.hooks.list({ chain: '8453', permission: 'beforeSwapReturnDelta', limit: 20 });
const hook = await q.hooks.get('8453', board.hooks[0].address);
console.log(hook.capabilities.map(c => c.title), hook.evidence.fingerprint);
const tape = await q.hooks.tape.swaps({ chain: '4663', hook: hook.hook, limit: 10 });
```

## Alerts

[@qhooks_bot](https://t.me/qhooks_bot) can follow any hook. Send `/hook <chainId> <address>`, or tap **Follow on Telegram** on a hook's profile. The bot tells you when:

- a new pool is initialised with the hook;
- the hook passes each batch of 25 finalized swaps;
- the LP fee moves by 10 basis points or more;
- the hook's deployed code changes.

`/list` shows what you follow. `/stop` turns everything off.
