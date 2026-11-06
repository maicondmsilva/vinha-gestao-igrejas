import {createHash} from 'node:crypto';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {financeDate} from '../../lib/finance-f1';
import {financeF5Command} from '../../lib/finance-f5';
import {parseFinanceOfx} from '../../lib/finance-ofx';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
const errors:Record<string,string>={ofx_entry_already_created:'Este movimento já foi utilizado, excluído ou conciliado. Atualize a lista para consultar o lançamento existente.',different_bank_account:'O arquivo pertence a outra conta bancária. Selecione ou cadastre a conta correta.',bank_transaction_changed:'O banco reenviou um identificador com dados diferentes. A importação foi recusada integralmente para revisão.',amount_difference:'Os totais selecionados no extrato e no livro são diferentes.',undo_reconciliation_first:'Desfaça a conciliação antes de corrigir o lançamento.',period_closed:'O período está fechado. Solicite reabertura administrativa.',closing_pending_review:'Existem pendências. Regularize-as ou solicite ao administrador um fechamento com ressalvas.',closing_admin_required:'Somente proprietário ou administrador pode reabrir o período.',invalid_month:'Selecione o último dia de um mês já encerrado e informe a justificativa.'};
function failure(error?:{code?:string;message?:string}){const code=error?.code;return json({error:errors[error?.message||'']||(code==='42501'?'Acesso financeiro não autorizado.':code==='40001'||code==='23505'?'A seleção ou o período mudou. Atualize antes de continuar.':['22023','22P02','22007','22008','23514','23502'].includes(code||'')?'Revise os dados, valores, conta e período. Nenhuma alteração parcial foi mantida.':'Resultado não confirmado. Preserve o pedido para consultar sem duplicar.')},code==='42501'?403:code==='40001'||code==='23505'?409:['22023','22P02','22007','22008','23514','23502'].includes(code||'')?400:503)}
async function run(r:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(r,'units.read');if(!auth||auth.response)return auth?.response||failure();const a=auth.access!;
 if(!['owner','admin','finance'].includes(a.membership.role))return failure({code:'42501'});
 let unit:string,action:string,data:Record<string,unknown>;
 try{
  if(write){const c=financeF5Command(JSON.parse(new TextDecoder().decode(await boundedBody(r,2097152))));unit=c.unitId;action=c.action;data=c.data;
   if(!a.membership.units.some(u=>u.id===unit))return failure({code:'42501'});
   if(c.action==='import'){const statement=parseFinanceOfx(c.ofx!),{accountIdentity,...safe}=statement;if(c.selected){if(c.selected.some(id=>!safe.transactions.some(t=>t.fitid===id)))throw Error('A seleção não corresponde ao arquivo OFX.');safe.transactions=safe.transactions.filter(t=>c.selected!.includes(t.fitid))}data={...data,...safe,sourceHash:createHash('sha256').update(c.ofx!+(c.selected?'|selecionados:'+JSON.stringify([...c.selected].sort()):'')).digest('hex'),accountHash:createHash('sha256').update(accountIdentity).digest('hex')};delete data.bank;delete data.currency;}
  }else{const p=new URL(r.url).searchParams;for(const k of p.keys())if(p.getAll(k).length>1)throw Error('Filtro repetido.');unit=p.get('unit')||'';action='snapshot';const account=p.get('account')||'';if(!uuidPattern.test(unit)||account&&!uuidPattern.test(account))throw Error('Selecione a igreja e a conta.');const from=financeDate(p.get('from')),to=financeDate(p.get('to'));if(to<from||Date.parse(to)-Date.parse(from)>366*86400000)throw Error('Selecione até 366 dias.');data={account,from,to};}
 }catch(e){return json({error:e instanceof Error?e.message:'Revise os dados.'},400)}
 if(!a.membership.units.some(u=>u.id===unit))return failure({code:'42501'});
 try{const result=await(a.client as unknown as OperationsClient).rpc('finance_f5',{p_org:a.membership.organization_id,p_unit:unit,p_action:action,p_data:data});if(result.error)return failure(result.error);if(write&&(result.data?.ok!==true||result.data.id!==data.id))return failure();return json(result.data)}catch{return failure()}
}
export const GET=(r:Request)=>run(r,false);
export const POST=(r:Request)=>run(r,true);
