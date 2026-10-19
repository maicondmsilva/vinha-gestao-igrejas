import test from 'node:test';
import assert from 'node:assert/strict';
import {rehearseMercadoSubscription as run} from '../app/api/payments/mercado-pago-subscription-rehearsal.ts';
const now=Date.parse('2026-10-19T12:00:00.000Z');
const input={requestId:'11111111-1111-4111-8111-111111111111',amountCents:100,payerEmail:'buyer@testuser.com',firstChargeAt:'2026-10-21T12:00:00.000Z',returnUrl:'https://teste.vinhaigrejas.com.br/pagamentos/assinatura/retorno'};
const token='APP_USR-synthetic-token-only';
const reply=value=>new Response(JSON.stringify(value));
test('ensaio isolado valida identidade antes de preparar assinatura pendente',async()=>{
 const calls=[];
 const result=await run(input,token,async(url,options)=>{calls.push({url,options});if(options.method==='GET')return reply({id:123,site_id:'MLB',tags:['test_user']});return reply({...JSON.parse(options.body),id:'synthetic',live_mode:false})},now);
 assert.equal(calls.length,2);assert.equal(calls[0].options.method,'GET');assert.equal(calls[1].options.method,'POST');assert.equal(JSON.parse(calls[1].options.body).status,'pending');assert.equal(result.paymentConfirmed,false);assert.equal(JSON.stringify(result).includes(token),false);
});
test('sem identidade de teste não envia assinatura',async()=>{let count=0;await assert.rejects(run(input,token,async()=>{count++;return reply({id:123,site_id:'MLB'})},now));assert.equal(count,1)});
test('entrada real ou inválida não chega ao transporte',async()=>{let count=0;await assert.rejects(run({...input,payerEmail:'real@example.com'},token,async()=>{count++},now));assert.equal(count,0)});
test('falha de criação não é repetida e não expõe detalhes sensíveis',async()=>{let count=0;await assert.rejects(run(input,token,async()=>{count++;return count===1?reply({id:123,site_id:'MLB',tags:['test_user']}):new Response('sensitive provider detail',{status:500})},now),/não repetir automaticamente/);assert.equal(count,2)});
