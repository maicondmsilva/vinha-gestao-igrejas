import {uuidPattern} from './private-files.ts';
export const financeSections=[['geral','Visão geral'],['lancamentos','Lançamentos'],['receber','Contas a receber'],['pagar','Contas a pagar'],['recebimentos','Contas recebedoras'],['arrecadacao','Arrecadação digital'],['conciliacao','Conciliação'],['fechamento','Fechamento mensal'],['relatorios','Relatórios e prestação de contas'],['contas','Contas bancárias e caixas'],['categorias','Categorias e subcategorias'],['centros','Centros de custo'],['fornecedores','Fornecedores']] as const;
export type FinanceSection=typeof financeSections[number][0];
export function financeSection(value:string|null):FinanceSection{return financeSections.find(([id])=>id===value)?.[0]||'geral'}
export function financeMoney(cents:string|bigint){const n=BigInt(cents),abs=(n<BigInt(0)?-n:n).toString().padStart(3,'0');return `${n<BigInt(0)?'− ':''}R$ ${abs.slice(0,-2).replace(/\B(?=(\d{3})+(?!\d))/g,'.')},${abs.slice(-2)}`}
export function financeDate(value:unknown){if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value)||!Number.isFinite(Date.parse(value+'T12:00:00Z'))||new Date(value+'T12:00:00Z').toISOString().slice(0,10)!==value)throw Error('Informe uma data válida.');return value}
export function financeCents(value:unknown){if(typeof value!=='string'||!/^\d{1,10}(?:,\d{1,2})?$/.test(value))throw Error('Informe o valor sem separador de milhar, por exemplo 1234,56.');const [a,b='']=value.split(','),n=BigInt(a)*BigInt(100)+BigInt(b.padEnd(2,'0'));if(n<BigInt(1)||n>BigInt('999999999999'))throw Error('Valor fora do limite.');return n.toString()}
function id(value:unknown,optional=false){if(optional&&(value===''||value==null))return '';if(typeof value!=='string'||!uuidPattern.test(value))throw Error('Selecione um cadastro válido.');return value.toLowerCase()}
function text(value:unknown,max:number,min=0){if(typeof value!=='string'||value.trim().length<min||value.length>max)throw Error('Revise os campos informados.');return value.trim()}
function exact(data:Record<string,unknown>,fields:string[]){if(Object.keys(data).some(k=>!fields.includes(k)))throw Error('Campo não permitido.');}
export function financeCommand(input:unknown){
 if(!input||typeof input!=='object'||Array.isArray(input))throw Error('Dados inválidos.');const raw=input as Record<string,unknown>;
 exact(raw,['action','unitId','data']);const unitId=id(raw.unitId);if(!raw.data||typeof raw.data!=='object'||Array.isArray(raw.data))throw Error('Dados inválidos.');const d=raw.data as Record<string,unknown>;
 if(raw.action==='catalog'){
  exact(d,['id','kind','name','direction','parent','shared','version','active','details']);
  if(!['account','category','center','supplier'].includes(String(d.kind))||typeof d.shared!=='boolean'||typeof d.active!=='boolean'||!Number.isInteger(d.version)||Number(d.version)<0)throw Error('Cadastro inválido.');
  const kind=String(d.kind),direction=kind==='category'?String(d.direction):'';if(kind==='category'&&!['income','expense'].includes(direction))throw Error('Escolha o tipo da categoria.');
  if(kind!=='category'&&(d.parent||d.direction)||kind==='account'&&d.shared)throw Error('Escopo inválido.');
  if(!d.details||typeof d.details!=='object'||Array.isArray(d.details))throw Error('Detalhes inválidos.');const detail=d.details as Record<string,unknown>;
  exact(detail,['document','email','phone','bank','number','description']);for(const value of Object.values(detail))text(value,200);
  return{action:'catalog' as const,unitId,data:{id:id(d.id),kind,name:text(d.name,120,2),direction,parent:id(d.parent,true),shared:d.shared,version:d.version,active:d.active,details:detail}};
 }
 if(raw.action==='entry'){
  exact(d,['id','kind','amount','description','account','destination','category','center','supplier','person','party','method','notes','competence','due','paid']);
  if(!['income','expense','transfer','opening'].includes(String(d.kind))||!['cash','pix','card','boleto','bank','other'].includes(String(d.method)))throw Error('Tipo inválido.');
  const data={id:id(d.id),kind:String(d.kind),amountCents:financeCents(d.amount),description:text(d.description,300,2),account:id(d.account),destination:id(d.destination,true),category:id(d.category,true),center:id(d.center,true),supplier:id(d.supplier,true),person:id(d.person,true),party:text(d.party??'',160),method:String(d.method),notes:text(d.notes??'',2000),competence:financeDate(d.competence),due:financeDate(d.due),paid:d.paid?financeDate(d.paid):''};
  if(data.person&&data.supplier||['income','expense'].includes(data.kind)&&!data.category||data.kind==='transfer'&&(!data.destination||data.account===data.destination)||['opening','transfer'].includes(data.kind)&&!data.paid)throw Error('Revise a classificação e as contas.');
  return{action:'entry' as const,unitId,data};
 }
 if(raw.action==='void'){
  exact(d,['id','version','reason','date','requestId']);if(!Number.isInteger(d.version)||Number(d.version)<1)throw Error('Versão inválida.');
  return{action:'void' as const,unitId,data:{id:id(d.id),version:d.version,reason:text(d.reason,300,2),date:financeDate(d.date),requestId:id(d.requestId)}};
 }
 throw Error('Ação inválida.');
}
export function financeQuery(request:Request){
 const p=new URL(request.url).searchParams;for(const key of p.keys())if(p.getAll(key).length>1)throw Error('Filtro repetido.');
 const units=(p.get('units')||'').split(',').map(v=>id(v));if(units.length>100||new Set(units).size!==units.length)throw Error('Seleção inválida.');
 if(p.get('action')==='choices')return{units,action:'choices',data:{search:text(p.get('search'),80,2)}};
 const from=financeDate(p.get('from')),to=financeDate(p.get('to'));if(to<from||(Date.parse(to)-Date.parse(from))/86400000>366)throw Error('Selecione um período de até 366 dias.');
 const page=Number(p.get('page')||1);if(!Number.isInteger(page)||page<1||page>10000)throw Error('Página inválida.');
 const kind=p.get('kind')||'',status=p.get('status')||'',dateBy=p.get('dateBy')||'due';
 const scope=p.get('scope')||'';if(scope&&!['titles'].includes(scope)||kind&&!['income','expense','transfer','opening'].includes(kind)||status&&!['pending','posted','settled','cancelled','reversed'].includes(status)||!['due','paid','competence'].includes(dateBy))throw Error('Filtro inválido.');
 return{units,action:'snapshot',data:{from,to,page,kind,status,dateBy,scope,subcategory:id(p.get('subcategory'),true),account:id(p.get('account'),true),category:id(p.get('category'),true),center:id(p.get('center'),true),search:text(p.get('search')||'',80)}};
}
