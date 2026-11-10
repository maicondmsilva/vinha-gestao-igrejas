import {financeMoney} from './finance-f1.ts';import {uuidPattern} from './private-files.ts';
export const financeHistoryLabels:Record<string,string>={kind:'Natureza',amount_cents:'Valor',description:'Descrição',account_id:'Conta',destination_id:'Conta de destino',category_id:'Categoria / subcategoria',center_id:'Centro de custo',supplier_id:'Fornecedor',person_id:'Pessoa',party_name:'Pessoa / fornecedor',method:'Forma de pagamento',notes:'Observações',competence_date:'Competência',due_date:'Vencimento',paid_date:'Data realizada',status:'Situação',reversed_date:'Data de estorno',principal_cents:'Principal liquidado',interest_cents:'Juros',fine_cents:'Multa',discount_cents:'Desconto',fee_cents:'Taxa',reversed_at:'Estorno da baixa',reason:'Justificativa'};
const words:Record<string,string>={income:'Entrada',expense:'Saída',transfer:'Transferência',opening:'Saldo inicial',pending:'Previsto',posted:'Realizado',settled:'Liquidado',cancelled:'Cancelado',cash:'Dinheiro',pix:'Pix',card:'Cartão',boleto:'Boleto',bank:'Transferência bancária',other:'Outro'};
export function financeHistoryValue(key:string,v:unknown,catalog:{id:string;name:string}[],party?:unknown){
 if(v===null||v===undefined||v==='')return'—';const text=String(v);
 if(key.endsWith('_cents'))return financeMoney(text);
 if((key==='person_id'||key==='supplier_id')&&typeof party==='string'&&party.trim())return party;
 return catalog.find(c=>c.id===text)?.name||words[text]||(uuidPattern.test(text)?'Cadastro vinculado (nome indisponível nesta consulta)':text);
}
