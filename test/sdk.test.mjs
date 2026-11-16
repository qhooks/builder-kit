import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createClient, feeRouterSwap, universalRouterSwap, predictCreate2Address, CREATE2_DEPLOYER, FEE_ROUTER, CHAINS, VERSION, withSlippage} from '../sdk/qhooks.mjs';
const extra = JSON.parse(await readFile(new URL('./fixtures/fee-router-extras.json',import.meta.url)));
const zero = '0x'+'0'.repeat(40), token='0x2222222222222222222222222222222222222222';
const pool = {chainId:'8453',poolId:'0x'+'a'.repeat(64),key:{currency0:zero,currency1:token,fee:3000,tickSpacing:60,hooks:zero}};
const options = {pool,zeroForOne:true,amountIn:100n,minOut:90n,deadline:2000000000};
function setup(extras=extra, status=200) {
 const calls=[];
 const q=createClient({fetch:async url=>{calls.push(url);return String(url).endsWith('/chains')?Response.json({chains:[{chainId:'8453',feeRouterDeployed:false}]}):status===200?Response.json(extras):new Response('<html>bad gateway</html>',{status});}});
 return {q,calls};
}

test('CREATE2 matches EIP1014 and the pinned real fee-router fixture',()=>{
 assert.equal(predictCreate2Address(zero,'0x'+'0'.repeat(64),'0x00'),'0x4d1a2e2bb4f88f0250f26ffff098b0b30b26bf38');
 assert.equal(predictCreate2Address(extra.deployer,extra.salt,extra.contracts.feeRouter.initCode),FEE_ROUTER);
});
test('router setup is returned only for the standard deployer and computed pinned address',async()=>{
 const {q,calls}=setup();const r=await q.feeRouterStatus('8453');
 assert.equal(r.deployed,false);assert.deepEqual(r.setup,{to:CREATE2_DEPLOYER,data:extra.salt+extra.contracts.feeRouter.initCode.slice(2),value:0n});assert.equal(calls.length,2);
 for(const mutate of [x=>x.deployer=token,x=>x.salt='0x'+'0'.repeat(64),x=>x.contracts.feeRouter.initCode='0x00',x=>x.contracts.feeRouter.address=token,x=>x.contracts.feeRouter.initCode='0x0',x=>delete x.contracts.feeRouter.initCode]){
  const x=structuredClone(extra);mutate(x);await assert.rejects(setup(x).q.feeRouterStatus('8453'));
 }
});
test('non-JSON setup and API/RPC errors retain HTTP status before JSON parsing',async()=>{
 await assert.rejects(setup(extra,502).q.feeRouterStatus('8453'),e=>e.status===502&&e.message==='HTTP 502'&&!(e instanceof SyntaxError));
 const q=createClient({rpc:{'8453':'https://rpc.invalid'},fetch:async()=>new Response('upstream failed',{status:502})});
 await assert.rejects(q.pools(),e=>e.status===502&&e.message==='HTTP 502');
 await assert.rejects(q.quote({...options}),e=>e.status===502&&e.message==='HTTP 502');
 await assert.rejects(q.modules(),e=>e.status===502&&e.message==='HTTP 502');
});
test('pool chain overrides and mixed-chain paths fail before any network or calldata output',async()=>{
 let calls=0;const q=createClient({fetch:async()=>{calls++;throw Error('no network');}});
 await assert.rejects(q.quote({...options,chainId:'56'}),/disagrees/);
 for(const make of [feeRouterSwap,universalRouterSwap])assert.throws(()=>make({...options,chainId:'56'}),/disagrees/);
 assert.throws(()=>feeRouterSwap({...options,chainId:'8453',hops:[{...pool,chainId:'56',key:pool.key,zeroForOne:true}]}),/disagrees/);
 assert.equal(calls,0);assert.equal(feeRouterSwap({...options,chainId:8453}).to,FEE_ROUTER);
});
test('fee basis points enforce the deployed 100-bps cap without silently clamping',()=>{
 for(const feeBps of [-1,101,10000,1.5,NaN,Infinity,'100'])assert.throws(()=>feeRouterSwap({...options,feeBps}),/Fee bps/);
 assert.equal(withSlippage(1000n,100n),990n);
 for(const feeBps of [0,100,100n])assert.equal(BigInt('0x'+feeRouterSwap({...options,feeBps}).data.slice(10+64*6,10+64*7)),BigInt(feeBps));
});
test('Elysium uses its own router; Monad does not invent a fee-router deployment',async()=>{
 const p={...pool,chainId:'99901'};const tx=feeRouterSwap({...options,pool:p});assert.equal(tx.to,'0xff208831ed6f0c4e3e3224effa45fae7906dc6c2');
 let reads=0;const q=createClient({rpc:{'99901':'https://rpc.invalid'},fetch:async(_u,o)=>{reads++;assert.equal(JSON.parse(o.body).params[0],CHAINS['99901'].feeRouter);return Response.json({result:'0x6000'});}});
 assert.deepEqual(await q.feeRouterStatus('99901'),{deployed:true,setup:null});assert.equal(reads,1);
 const m=createClient({fetch:async()=>{throw Error('no fetch for unavailable route');}});
 assert.equal((await m.feeRouterStatus('143')).setup,null);assert.throws(()=>feeRouterSwap({...options,pool:{...pool,chainId:'143'}}),/unavailable/);
 assert.equal(universalRouterSwap({...options,pool:{...pool,chainId:'143'}}).to,CHAINS['143'].router);
});
test('standalone SDK imports without relative dependencies and package versions agree',async()=>{
 const source=await readFile(new URL('../sdk/qhooks.mjs',import.meta.url),'utf8');
 const standalone=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
 assert.equal(standalone.VERSION,VERSION);assert.equal(VERSION,JSON.parse(await readFile(new URL('../package.json',import.meta.url))).version);
 assert.deepEqual(Object.keys(CHAINS).sort(),['1','143','42161','4663','56','8453','99901'].sort());
});
