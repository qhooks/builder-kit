import {keccak_256} from './vendor/hashes/sha3.js';
export const hashHex = hex => '0x' + Array.from(keccak_256(Uint8Array.from(hex.slice(2).match(/../g)||[], b=>parseInt(b,16))), b=>b.toString(16).padStart(2,'0')).join('');
