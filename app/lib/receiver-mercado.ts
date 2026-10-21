import {createHash,randomBytes} from 'node:crypto';
import type {ReceiverEnvironment} from './finance-receivers.ts';
export type MercadoReceiverToken={access_token:string;refresh_token:string;expires_at:number;user_id:string};
type Fetch=typeof fetch;
function config(environment:ReceiverEnvironment){const prefix=environment==='sandbox'?'FINANCE_MP_TEST':'FINANCE_MP_LIVE',id=process.env[prefix+'_CLIENT_ID'],secret=process.env[prefix+'_CLIENT_SECRET'],redirect=process.env[prefix+'_REDIRECT_URI'];if(!id||!/^\d+$/.test(id)||!secret||!redirect)throw Error('Autorização Mercado Pago não configurada neste ambiente.');const u=new URL(redirect);if((u.protocol!=='https:'&&!(environment==='sandbox'&&u.hostname==='127.0.0.1'))||u.username||u.password||u.search||u.hash||u.pathname!=='/api/finance-receivers/callback')throw Error('Retorno OAuth inválido.');return{id,secret,redirect}}
export function mercadoReceiverConfigured(e:ReceiverEnvironment){try{config(e);return true}catch{return false}}
export function mercadoReceiverStart(e:ReceiverEnvironment){const c=config(e),state=randomBytes(32).toString('base64url'),verifier=randomBytes(48).toString('base64url'),url=new URL('https://auth.mercadopago.com/authorization');url.search=new URLSearchParams({response_type:'code',client_id:c.id,platform_id:'mp',state,redirect_uri:c.redirect,code_challenge:createHash('sha256').update(verifier).digest('base64url'),code_challenge_method:'S256'}).toString();return{url:url.href,state,verifier,redirect:c.redirect}}
async function body(r:Response){if(!r.ok)throw Error('O Mercado Pago recusou a autorização.');const raw=await r.text();if(raw.length>65536)throw Error('Resposta inválida do provedor.');return JSON.parse(raw) as Record<string,unknown>}
export async function mercadoReceiverExchange(e:ReceiverEnvironment,input:{code:string;verifier:string}|{refresh:string},transport:Fetch=fetch){
 const c=config(e),d=await body(await transport('https://api.mercadopago.com/oauth/token',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({client_id:c.id,client_secret:c.secret,test_token:e==='sandbox',...('code'in input?{grant_type:'authorization_code',code:input.code,code_verifier:input.verifier,redirect_uri:c.redirect}:{grant_type:'refresh_token',refresh_token:input.refresh})}),redirect:'error',signal:AbortSignal.timeout(15000)}));
 if(typeof d.access_token!=='string'||typeof d.refresh_token!=='string'||!/^\d+$/.test(String(d.user_id))||!Number.isSafeInteger(d.expires_in)||Number(d.expires_in)<60||typeof d.live_mode!=='boolean'||d.live_mode!==(e==='production'))throw Error('Conta ou ambiente não confirmado pelo Mercado Pago.');
 return{access_token:d.access_token,refresh_token:d.refresh_token,user_id:String(d.user_id),expires_at:Date.now()+Number(d.expires_in)*1000} satisfies MercadoReceiverToken;
}
export async function mercadoReceiverIdentity(token:MercadoReceiverToken,e:ReceiverEnvironment,transport:Fetch=fetch){
 const d=await body(await transport('https://api.mercadopago.com/users/me',{headers:{Authorization:'Bearer '+token.access_token},redirect:'error',signal:AbortSignal.timeout(15000)}));
 const tags=Array.isArray(d.tags)?d.tags:[],isTest=tags.includes('test_user');if(String(d.id)!==token.user_id||d.site_id!=='MLB'||isTest!==(e==='sandbox'))throw Error('Titular ou ambiente da conta divergente.');
 const name=[d.first_name,d.last_name].filter(x=>typeof x==='string').join(' ').trim()||String(d.nickname||'');if(!name||name.length>160)throw Error('Titular não informado pelo provedor.');
 return{externalId:String(d.id),holder:name,providerStatus:'identity_verified',expiresAt:new Date(token.expires_at).toISOString()};
}
