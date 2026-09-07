import { env } from 'cloudflare:workers';
const bytes=(value:string)=>Uint8Array.from(atob(value),c=>c.charCodeAt(0));
const encoded=(value:Uint8Array)=>btoa(String.fromCharCode(...value));
async function key(){const secret=(env as any).PAYMENT_CREDENTIALS_MASTER_KEY;if(!secret)throw new Error('Cofre de credenciais indisponível.');const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(secret));return crypto.subtle.importKey('raw',digest,'AES-GCM',false,['encrypt','decrypt']);}
export async function encryptSecret(value:string){const iv=crypto.getRandomValues(new Uint8Array(12)),data=await crypto.subtle.encrypt({name:'AES-GCM',iv},await key(),new TextEncoder().encode(value));return {ciphertext:encoded(new Uint8Array(data)),iv:encoded(iv),hint:`••••${value.slice(-4)}`};}
export async function decryptSecret(ciphertext?:string|null,iv?:string|null){if(!ciphertext||!iv)return null;const data=await crypto.subtle.decrypt({name:'AES-GCM',iv:bytes(iv)},await key(),bytes(ciphertext));return new TextDecoder().decode(data);}
