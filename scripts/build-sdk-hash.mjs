// Regenerate the embedded hash without changing the standalone SDK's other code.
// node scripts/build-sdk-hash.mjs [path-to-esbuild-module]
import {readFile, writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
const api = await import(process.argv[2] ? pathToFileURL(process.argv[2]).href : 'esbuild');
const {build} = api.default || api;
const result = await build({entryPoints:['scripts/hash-entry.mjs'], bundle:true, write:false, format:'iife', globalName:'qhooksKeccak', platform:'browser', target:'es2020', minify:true, legalComments:'none'});
const license = await readFile('scripts/vendor/hashes/LICENSE','utf8');
const first = '// BEGIN bundled noble Keccak-256 (build input: scripts/hash-entry.mjs)';
const last = '// END bundled noble Keccak-256';
const file = 'sdk/qhooks.mjs', source = await readFile(file,'utf8');
const a = source.indexOf(first), b = source.indexOf(last);
if (a < 0 || b <= a || source.indexOf(first,a+1) !== -1) throw Error('SDK hash markers are missing or duplicated.');
const generated = first+'\n/*\n'+license+'*/\n'+result.outputFiles[0].text+last;
await writeFile(file,source.slice(0,a)+generated+source.slice(b+last.length));
