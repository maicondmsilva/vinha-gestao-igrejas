'use client';
import {useState} from 'react';
import {Dialog,PartyPicker,type Entry,type Catalog} from './FinanceModule';
import FinanceClassification from './FinanceClassification';
import FinanceFiles from './FinanceFiles';
type Command={action:string;unitId:string;data:Record<string,unknown>};
export function canEditFinanceEntry(e:Entry){return ['pending','posted','settled'].includes(e.status)&&!e.reversal_id&&!e.settlement_id&&!e.notes.startsWith('F4 · Pedido ')}
export default function FinanceEntryEditor({entry,catalog,locked,close,onCommand}:{entry:Entry;catalog:Catalog[];locked:boolean;close:()=>void;onCommand:(c:Command)=>Promise<boolean|void>}){
 const [error,setError]=useState(''),[saving,setSaving]=useState(false),[kind,setKind]=useState(entry.kind),[paid,setPaid]=useState(['posted','settled'].includes(entry.status)),[party,setParty]=useState({name:entry.party_name,id:entry.person_id||entry.supplier_id||'',kind:entry.person_id?'member':entry.supplier_id?'supplier':''});
 const blocked=locked||saving,amount=(entry.original_amount_cents||entry.amountCents).padStart(3,'0'),items=catalog.filter(c=>c.active&&(c.unit_id===entry.unit_id||c.unit_id===null)),cashRequired=['transfer','opening'].includes(kind);
 return <Dialog title={'Editar lançamento'+(entry.code?' '+entry.code:'')} locked={blocked} close={close}>
 <p>Altere os dados e a situação do lançamento. Código, anexos e histórico serão preservados. Uma ocorrência de série é alterada individualmente.</p>
 <p className="f1-alert">Ao salvar, a contabilização e as baixas anteriores serão revertidas nas datas originais. Se marcar como pago/recebido, uma nova contabilização será criada; juros, multa, desconto e taxas das baixas ativas serão mantidos. Ao desmarcar, o valor principal voltará a ficar em aberto. Períodos fechados não permitem essa correção.</p>
 <form onSubmit={async e=>{e.preventDefault();if(blocked)return;const f=new FormData(e.currentTarget);setError('');setSaving(true);try{const ok=await onCommand({action:'edit_entry',unitId:entry.unit_id,data:{id:crypto.randomUUID(),title:entry.id,version:entry.version,kind,amount:f.get('amount'),description:f.get('description'),account:f.get('account'),destination:kind==='transfer'?f.get('destination'):'',category:['income','expense'].includes(kind)?f.get('category'):'',center:f.get('center')||'',competence:f.get('competence'),due:f.get('due'),method:f.get('method'),notes:f.get('notes')||'',person:party.kind==='member'?party.id:'',supplier:party.kind==='supplier'?party.id:'',party:party.name,paid:paid||cashRequired?f.get('paid'):'',reason:f.get('reason')}});if(ok!==true)throw Error('Edição não confirmada. Confira o aviso e atualize antes de repetir.');close()}catch(e){setError(e instanceof Error?e.message:'Edição não confirmada.')}finally{setSaving(false)}}}>
 <fieldset disabled={blocked}><div className="f1-form-grid">
 <label>Natureza<select value={kind} onChange={e=>setKind(e.target.value)}>{Object.entries({income:'Entrada',expense:'Saída',transfer:'Transferência',opening:'Saldo inicial'}).map(([v,n])=><option key={v} value={v}>{n}</option>)}</select></label>
 <label>Valor principal<input name="amount" required inputMode="decimal" defaultValue={amount.slice(0,-2)+','+amount.slice(-2)}/></label>
 <label className="wide">Descrição<input name="description" required minLength={2} maxLength={300} defaultValue={entry.description}/></label>
 <label>Conta<select name="account" required defaultValue={entry.account_id||''}><option value="">Selecione</option>{items.filter(c=>c.kind==='account'&&c.unit_id===entry.unit_id).map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
 {kind==='transfer'&&<label>Conta de destino<select name="destination" required defaultValue={entry.destination_id||''}><option value="">Selecione</option>{items.filter(c=>c.kind==='account'&&c.unit_id===entry.unit_id).map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>}
 {['income','expense'].includes(kind)&&<FinanceClassification key={kind} catalog={items} direction={kind} initialCategory={kind===entry.kind?entry.category_id||'':''}/>}
 <label>Centro de custo<select name="center" defaultValue={entry.center_id||''}><option value="">Sem centro de custo</option>{items.filter(c=>c.kind==='center').map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
 <label>Forma<select name="method" defaultValue={entry.method}>{Object.entries({cash:'Dinheiro',pix:'Pix',card:'Cartão',boleto:'Boleto',bank:'Transferência bancária',other:'Outro'}).map(([id,name])=><option key={id} value={id}>{name}</option>)}</select></label>
 <label>Competência<input name="competence" type="date" required defaultValue={entry.competence_date}/></label><label>Vencimento<input name="due" type="date" required defaultValue={entry.due_date}/></label>
 <div className="wide"><PartyPicker unit={entry.unit_id} value={party} change={setParty} disabled={blocked}/></div>
 <label><input type="checkbox" checked={paid||cashRequired} disabled={cashRequired} onChange={e=>setPaid(e.target.checked)}/>{kind==='expense'?'Pago':kind==='income'?'Recebido':'Realizado'}</label>
 {(paid||cashRequired)&&<label>Data da realização<input name="paid" type="date" required defaultValue={entry.paid_date||new Date().toLocaleDateString('en-CA')}/></label>}
 <label className="wide">Observações<textarea name="notes" maxLength={2000} defaultValue={entry.notes}/></label>
 <label className="wide">Motivo da alteração<input name="reason" required minLength={2} maxLength={300}/></label>
 <label className="wide"><input type="checkbox" required/>Confirmo a correção e a atualização dos saldos e das baixas descritas acima.</label>
 </div></fieldset>{error&&<p role="alert" className="f1-alert">{error}</p>}<div className="f1-form-actions"><button type="button" disabled={blocked} className="f1-secondary" onClick={close}>Voltar</button><button disabled={blocked}>Salvar alterações</button></div></form>
 <FinanceFiles unitId={entry.unit_id} entryId={entry.id} disabled={blocked} initiallyOpen/></Dialog>;
}
