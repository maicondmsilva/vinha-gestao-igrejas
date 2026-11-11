import {uuidPattern} from './private-files.ts';
export const financeSections=[['geral','Visão geral'],['lancamentos','Lançamentos'],['receber','Contas a receber'],['pagar','Contas a pagar'],['conciliacao','Conciliação'],['fechamento','Fechamento mensal'],['relatorios','Relatórios e prestação de contas'],['contas','Contas bancárias e caixas'],['categorias','Categorias e subcategorias'],['centros','Centros de custo'],['fornecedores','Fornecedores'],['recebimentos','Contas recebedoras'],['arrecadacao','Recebimentos digitais']] as const;
/** Day-to-day work first; registrations and payment setup apart, so the person finds the task without scanning 13 tabs. */
export const financeGroups:readonly {title:string;sections:readonly FinanceSection[]}[]=[{title:'Operação',sections:['geral','lancamentos','receber','pagar','conciliacao','fechamento','relatorios']},{title:'Cadastros e recebimentos',sections:['contas','categorias','centros','fornecedores','recebimentos','arrecadacao']}];
/** Short names for tabs and the side menu; the page title keeps the full name. */
export const financeShortLabels:Record<string,string>={relatorios:'Relatórios',contas:'Contas e caixas',categorias:'Categorias'};
export const financeLabel=(id:string)=>financeShortLabels[id]||financeSections.find(([x])=>x===id)?.[1]||'';
export type FinanceSection=typeof financeSections[number][0];
export function financeSection(value:string|null):FinanceSection{return financeSections.find(([id])=>id===value)?.[0]||'geral'}
export function financeMoney(cents:string|bigint){const n=BigInt(cents),abs=(n<BigInt(0)?-n:n).toString().padStart(3,'0');return `${n<BigInt(0)?'− ':''}R$ ${abs.slice(0,-2).replace(/\B(?=(\d{3})+(?!\d))/g,'.')},${abs.slice(-2)}`}
/** On-screen dates: "2026-11-05" becomes "05/11/2026". Exports and date inputs keep the ISO form. */
export function financeDay(value:unknown){if(typeof value!=='string')return '';const m=/^(\d{4})-(\d{2})-(\d{2})/.exec(value);return m?`${m[3]}/${m[2]}/${m[1]}`:value}
const monthNames=['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez'];
/** On-screen months: "2026-06" becomes "jun/2026". */
export function financeMonth(value:unknown){if(typeof value!=='string')return '';const m=/^(\d{4})-(\d{2})$/.exec(value);return m&&Number(m[2])>=1&&Number(m[2])<=12?`${monthNames[Number(m[2])-1]}/${m[1]}`:value}
export function financeDate(value:unknown){if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value)||!Number.isFinite(Date.parse(value+'T12:00:00Z'))||new Date(value+'T12:00:00Z').toISOString().slice(0,10)!==value)throw Error('Informe uma data válida.');return value}
/**
 * Reads money the way people type it in Brazil and returns the canonical "1234,56" form, or null.
 * Accepts "R$ 1.234,56", "1.234,56", "1234,56", "1234", "1.234" (thousands) and "12.50" (dot as decimal,
 * only when one dot is followed by 1–2 digits and there is no comma). Ambiguous input ("1.23,4", "1,000.50") is null.
 */
export function financeMoneyInput(value:unknown){
 if(typeof value!=='string')return null;
 const clean=value.replace(/^\s*R\$/i,'').replace(/[\s\u00a0]/g,'');
 if(!clean)return null;
 let int:string,dec='';
 if(clean.includes(',')){const parts=clean.split(',');if(parts.length!==2||!/^\d{1,2}$/.test(parts[1]))return null;[int,dec]=parts}
 else if(/^\d+\.\d{1,2}$/.test(clean)){[int,dec]=clean.split('.')}
 else int=clean;
 if(/^\d{1,3}(?:\.\d{3})+$/.test(int))int=int.replace(/\./g,'');
 if(!/^\d{1,10}$/.test(int))return null;
 return dec?int+','+dec:int;
}
/** Canonical display for a money field after the person leaves it: "1.234,56". Invalid input is returned unchanged. */
export function financeMoneyField(value:string){const canonical=financeMoneyInput(value);if(canonical===null)return value;const [a,b='']=canonical.split(','),int=BigInt(a).toString();return int.replace(/\B(?=(\d{3})+(?!\d))/g,'.')+','+b.padEnd(2,'0')}
export function financeCents(value:unknown){const canonical=financeMoneyInput(value);if(canonical===null)throw Error('Informe um valor válido, por exemplo 1.234,56.');const [a,b='']=canonical.split(','),n=BigInt(a)*BigInt(100)+BigInt(b.padEnd(2,'0'));if(n<BigInt(1)||n>BigInt('999999999999'))throw Error('Valor fora do limite.');return n.toString()}
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
 if(raw.action==='delete'){
  exact(d,['id','version']);if(!Number.isInteger(d.version)||Number(d.version)<1)throw Error('Versão inválida.');
  return{action:'delete' as const,unitId,data:{id:id(d.id),version:d.version}};
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
 const pageSize=Number(p.get('pageSize')||30);if(!Number.isInteger(pageSize)||pageSize<1||pageSize>150)throw Error('Escolha até 150 lançamentos por página.');
 const kind=p.get('kind')||'',status=p.get('status')||'',dateBy=p.get('dateBy')||'due';
 const scope=p.get('scope')||'';if(scope&&!['titles'].includes(scope)||kind&&!['income','expense','transfer','opening'].includes(kind)||status&&!['pending','posted','settled','cancelled','reversed'].includes(status)||!['due','paid','competence'].includes(dateBy))throw Error('Filtro inválido.');
 return{units,action:'snapshot',data:{from,to,page,pageSize,kind,status,dateBy,scope,subcategory:id(p.get('subcategory'),true),account:id(p.get('account'),true),category:id(p.get('category'),true),center:id(p.get('center'),true),search:text(p.get('search')||'',80)}};
}
