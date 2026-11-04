// Quote a buy on the first listed QHooks pool on Base and build the swap transaction (nothing is sent).
// Run: node examples/quote.mjs [traderAddress]
import { createClient, withSlippage } from '../sdk/qhooks.mjs';

const trader = process.argv[2] || '0x0000000000000000000000000000000000000001';
const q = createClient({ rpc: { '8453': 'https://mainnet.base.org' } });
const pools = await q.pools({ chain: '8453' });
if (!pools.length) { console.log('No listed pools on Base yet.'); process.exit(0); }
const pool = pools[0];
const buy = pool.key.currency0 === pool.quote.address; // quote token -> launch token
const amountIn = 20_000000n; // 20 USDC
const { amountOut } = await q.quote({ pool, zeroForOne: buy, amountIn, trader });
const tx = q.universalRouterSwap({ pool, zeroForOne: buy, amountIn, minOut: withSlippage(amountOut, 100) });
console.log({ amountOut: amountOut.toString(), tx });
