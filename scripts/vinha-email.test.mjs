import {test} from 'node:test';
import assert from 'node:assert/strict';
import {vinhaEmail} from '../shared/vinha-email.ts';
import {sendMemberReviewEmails} from '../app/lib/member-review-email.ts';

test('e-mail tem marca e cores Vinha',()=>{const {html,text}=vinhaEmail({title:'Seu cadastro precisa de ajuste',intro:'Olá!',church:'Igreja Sede'});for(const t of ['#193f30','#d9b960','Gestão que frutifica','Igreja Sede','Você recebeu este e-mail porque tem cadastro na Vinha'])assert.ok(html.includes(t),t);assert.match(text,/Seu cadastro precisa de ajuste/)});
test('itens viram lista',()=>{const {html,text}=vinhaEmail({title:'T',intro:'I',items:['CPF','Celular']});assert.match(html,/<li[^>]*>CPF<\/li>/);assert.match(html,/<li[^>]*>Celular<\/li>/);assert.match(text,/- CPF\n- Celular/)});
test('texto escapa HTML',()=>{const {html}=vinhaEmail({title:'<script>alert(1)</script>',intro:'a & b',items:['<b>x</b>']});assert.doesNotMatch(html,/<script>/);assert.match(html,/&lt;script&gt;/);assert.match(html,/a &amp; b/)});
test('botão só com link https',()=>{assert.match(vinhaEmail({title:'T',intro:'I',action:{label:'Corrigir meu cadastro',url:'https://app.vinhaigrejas.com.br/membro/x?corrigir=1'}}).html,/href="https:\/\/app\.vinhaigrejas\.com\.br\/membro\/x\?corrigir=1"/);assert.throws(()=>vinhaEmail({title:'T',intro:'I',action:{label:'x',url:'javascript:alert(1)'}}))});

const job={id:'d0000000-0000-4000-8000-000000000001',recipient:'ana@example.invalid',subject:'Seu cadastro na Igreja Sede precisa de ajuste',items:['CPF'],reason:'CPF não confere',church:'Igreja Sede',slug:'igreja-sede'};
function fake(){const calls=[];return{calls,client:{rpc:async(name,args)=>{calls.push([name,args]);if(name==='member_review_email_batch')return{data:[job],error:null};return{data:null,error:null}}}}}
const smtp={EVENT_EMAIL_ENABLED:'true',EVENT_SMTP_HOST:'smtp.hostinger.com',EVENT_SMTP_USER:'notificacoes@vinhaigrejas.com.br',EVENT_SMTP_PORT:'465',EVENT_SMTP_PASSWORD:'x'};
test('sem SMTP, não reserva nem envia',async()=>{const f=fake();const r=await sendMemberReviewEmails(f.client,{});assert.deepEqual(r,{sent:0,failed:0,waitingConfiguration:true});assert.equal(f.calls.length,0)});
test('envio com sucesso marca enviado, com o link para corrigir',async()=>{const f=fake();const sent=[];const r=await sendMemberReviewEmails(f.client,smtp,20,async m=>{sent.push(m)});assert.deepEqual(r,{sent:1,failed:0,waitingConfiguration:false});assert.equal(sent[0].to,'ana@example.invalid');assert.match(sent[0].html,/membro\/igreja-sede\?corrigir=1/);assert.match(sent[0].html,/CPF não confere/);assert.deepEqual(f.calls.at(-1),['member_review_email_mark',{p_id:job.id,p_ok:true,p_error:null}])});
test('falha no SMTP marca falha e reagenda',async()=>{const f=fake();const r=await sendMemberReviewEmails(f.client,smtp,20,async()=>{throw Error('SMTP fora do ar')});assert.deepEqual(r,{sent:0,failed:1,waitingConfiguration:false});const mark=f.calls.at(-1);assert.equal(mark[0],'member_review_email_mark');assert.equal(mark[1].p_ok,false);assert.match(mark[1].p_error,/SMTP/)});
