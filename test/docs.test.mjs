import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createClient,withSlippage} from '../sdk/qhooks.mjs';
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const block=text=>text.split('```').find(x=>x.includes("import { createClient"));
const body=text=>block(text).replace(/^js\s*/,'').replace(/^import .*;\s*$/gm,'');
const zero='0x'+'0'.repeat(40),token='0x2222222222222222222222222222222222222222';
test('API quickstart runs with an empty list and with a native-quoted pool; no undefined trader',async()=>{
 const source=await readFile(new URL('../docs/api.md',import.meta.url),'utf8');
 for(const empty of [true,false]){
  let quotes=0;const pool={chainId:'8453',poolId:'0x'+'a'.repeat(64),quote:{address:zero,decimals:18},key:{currency0:zero,currency1:token,fee:3000,tickSpacing:60,hooks:zero}};
  const wrapped=opts=>createClient({...opts,fetch:async(url,request)=>{
   if(String(url).includes('/pools'))return Response.json({pools:empty?[]:[pool]});
   const rpc=JSON.parse(request.body);assert.equal(rpc.method,'eth_call');assert.equal(rpc.params[0].from,'0x0000000000000000000000000000000000000001');quotes++;
   return Response.json({result:'0x'+(1000n).toString(16).padStart(64,'0')+(21000n).toString(16).padStart(64,'0')});
  }});
  await new AsyncFunction('createClient','withSlippage','console',body(source))(wrapped,withSlippage,{log(){}});
  assert.equal(quotes,empty?0:1);
 }
});
test('Discover example retains one chain across hook selection, detail and Tape; empty list recovers',async()=>{
 const source=await readFile(new URL('../docs/discover.md',import.meta.url),'utf8');
 for(const empty of [true,false]){
  let tape=0;const fake=()=>({hooks:{list:async({chain})=>{assert.equal(chain,'8453');return {hooks:empty?[]:[{address:token}]};},get:async(chain,address)=>{assert.equal(chain,'8453');assert.equal(address,token);return {hook:token,capabilities:[],evidence:{fingerprint:'fixture'}};},tape:{swaps:async({chain,hook})=>{assert.equal(chain,'8453');assert.equal(hook,token);tape++;return {rows:[]};}}}});
  await new AsyncFunction('createClient','console',body(source))(fake,{log(){}});assert.equal(tape,empty?0:1);
 }
});
