import test from 'node:test';
import assert from 'node:assert/strict';
import {billingEvent,billingEventApplicable} from '../app/lib/supabase/billing-rules.ts';
const now=Date.UTC(2026,9,15,15),day=86400000;
test('aviso de vencimento somente dentro de três dias',()=>{assert.equal(billingEvent({status:'open',due_at:now+3*day},now),'upcoming');assert.equal(billingEvent({status:'open',due_at:now+3*day+1},now),null)});
test('atraso não é aviso de vencimento próximo',()=>{assert.equal(billingEvent({status:'open',due_at:now-1},now),'overdue');assert.equal(billingEventApplicable({status:'open',due_at:now-1},'upcoming',now),false)});
test('cobrança quitada não recebe lembrete de atraso',()=>{const invoice={status:'paid',due_at:now-day,paid_at:now};assert.equal(billingEventApplicable(invoice,'overdue',now),false);assert.equal(billingEvent(invoice,now),'paid')});
test('cobrança cancelada não recebe mensagem',()=>{for(const event of ['upcoming','overdue','paid'])assert.equal(billingEventApplicable({status:'cancelled',due_at:now},event,now),false)});
test('não enviar recibos antigos ao ativar notificações',()=>{assert.equal(billingEvent({status:'paid',due_at:now-30*day,paid_at:now-29*day},now),null);assert.equal(billingEvent({status:'paid',due_at:now},now),null)});
