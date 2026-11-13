// Pessoas · gestão: filtros avançados, duplicados, histórico, novos convertidos, ações em lote e exportação.
import {uuidPattern} from './private-files.ts';

export type PeopleFilters={cell?:string;network?:string;gender?:string;ageMin?:number;ageMax?:number;baptized?:boolean;tag?:string;converts?:boolean};
export const advancedKeys=['cell','network','gender','ageMin','ageMax','baptized','tag','converts'] as const;
export const genders=['Masculino','Feminino'] as const;
export const ageRanges=[['','Todas as idades'],['0-11','Crianças (até 11)'],['12-17','Adolescentes (12 a 17)'],['18-29','Jovens (18 a 29)'],['30-59','Adultos (30 a 59)'],['60-','60 anos ou mais']] as const;

/** Lê os filtros avançados da URL. Lança erro com mensagem curta quando algo não confere. */
export function peopleFilters(params:URLSearchParams):PeopleFilters{
 const f:PeopleFilters={};
 for(const key of ['cell','network'] as const){const v=params.get(key);if(v){if(!uuidPattern.test(v))throw Error('Célula ou rede inválida.');f[key]=v.toLowerCase()}}
 const gender=params.get('gender');if(gender){if(!(genders as readonly string[]).includes(gender))throw Error('Gênero inválido.');f.gender=gender}
 for(const key of ['ageMin','ageMax'] as const){const v=params.get(key);if(v){if(!/^\d{1,3}$/.test(v)||Number(v)>120)throw Error('Faixa etária inválida.');f[key]=Number(v)}}
 if(f.ageMin!==undefined&&f.ageMax!==undefined&&f.ageMin>f.ageMax)throw Error('Faixa etária inválida.');
 const baptized=params.get('baptized');if(baptized){if(!['sim','nao'].includes(baptized))throw Error('Filtro de batismo inválido.');f.baptized=baptized==='sim'}
 const tag=(params.get('tag')||'').trim();if(tag){if(tag.length>80)throw Error('Marcador muito longo.');f.tag=tag}
 if(params.get('converts')==='1')f.converts=true;
 return f;
}
export const hasAdvanced=(f:PeopleFilters)=>Object.keys(f).length>0;
/** "18-29" → {ageMin:18, ageMax:29}; "60-" → {ageMin:60}. */
export function ageRange(value:string):{ageMin?:string;ageMax?:string}{
 const m=/^(\d+)-(\d*)$/.exec(value);if(!m)return{};
 return{...(m[1]!=='0'?{ageMin:m[1]}:{}),...(m[2]?{ageMax:m[2]}:{})};
}

export const followupLabels:Record<string,string>={pending:'Aguardando contato',contacted:'Contato feito',in_cell:'Em uma célula',integrated:'Integrado',stopped:'Sem retorno'};
export const followupOrder=['pending','contacted','in_cell','integrated','stopped'] as const;
export const reasonLabels:Record<string,string>={cpf:'Mesmo CPF',phone:'Mesmo celular',name:'Mesmo nome',birth:'Mesmo primeiro nome e nascimento'};
export const timelineIcons:Record<string,string>={record:'✎',visit:'⌂',faith:'✝',journey:'➜',family:'♥',cell:'◎',app:'▣',service:'♪'};
export const bulkActions=[['journey','Mudar etapa'],['tag','Adicionar marcador'],['untag','Remover marcador'],['notify','Enviar comunicado']] as const;
export const journeys=['Visitante','Em integração','Membro'] as const;

const ids=(v:unknown,max:number)=>{
 if(!Array.isArray(v)||v.length<1||v.length>max||v.some(x=>typeof x!=='string'||!uuidPattern.test(x)))throw Error(`Escolha de 1 a ${max} pessoas.`);
 return [...new Set(v.map(x=>(x as string).toLowerCase()))];
};
const text=(v:unknown,min:number,max:number,msg:string)=>{if(typeof v!=='string'||v.trim().length<min||v.trim().length>max)throw Error(msg);return v.trim()};
const unit=(v:unknown)=>{if(typeof v!=='string'||!uuidPattern.test(v))throw Error('Escolha a igreja.');return v};

/** Corpo do POST de ações em lote. */
export function bulkInput(body:unknown){
 const b=(body&&typeof body==='object'?body:{}) as Record<string,unknown>;
 const action=b.action;
 if(!['journey','tag','untag','notify','notify_preview'].includes(action as string))throw Error('Ação inválida.');
 const notify=action==='notify'||action==='notify_preview';
 const data:Record<string,unknown>={ids:ids(b.ids,notify?250:500)};
 if(action==='journey'){if(!(journeys as readonly string[]).includes(b.value as string))throw Error('Escolha a etapa.');data.value=b.value}
 if(action==='tag'||action==='untag')data.value=text(b.value,1,40,'O marcador precisa ter de 1 a 40 caracteres.');
 if(action==='notify'){
  data.title=text(b.title,2,65,'O título precisa ter de 2 a 65 caracteres.');
  data.body=text(b.body,2,240,'A mensagem precisa ter de 2 a 240 caracteres.');
  if(typeof b.request!=='string'||!uuidPattern.test(b.request))throw Error('Pedido inválido. Atualize a página.');
  data.request=b.request;
 }
 return{unit:unit(b.unit),action:action as string,data};
}
export function mergeInput(body:unknown){
 const b=(body&&typeof body==='object'?body:{}) as Record<string,unknown>;
 if(b.action!=='merge'&&b.action!=='dismiss')throw Error('Ação inválida.');
 if(typeof b.keep!=='string'||typeof b.remove!=='string'||!uuidPattern.test(b.keep)||!uuidPattern.test(b.remove)||b.keep===b.remove)throw Error('Escolha os dois cadastros.');
 return{unit:unit(b.unit),action:b.action,data:{keep:b.keep,remove:b.remove}};
}
export function convertInput(body:unknown){
 const b=(body&&typeof body==='object'?body:{}) as Record<string,unknown>;
 if(typeof b.person!=='string'||!uuidPattern.test(b.person))throw Error('Escolha a pessoa.');
 const data:Record<string,unknown>={person:b.person};
 if('convertedAt' in b){if(b.convertedAt!==''&&(typeof b.convertedAt!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(b.convertedAt)))throw Error('Data da decisão inválida.');data.convertedAt=b.convertedAt}
 if('status' in b){if(!(followupOrder as readonly string[]).includes(b.status as string))throw Error('Etapa do acompanhamento inválida.');data.status=b.status}
 if('followup' in b){if(b.followup!==''&&(typeof b.followup!=='string'||!uuidPattern.test(b.followup)))throw Error('Responsável inválido.');data.followup=b.followup}
 if('note' in b){if(typeof b.note!=='string'||b.note.length>500)throw Error('A observação pode ter até 500 caracteres.');data.note=b.note}
 return{unit:unit(b.unit),data};
}

/** Mensagem de erro do banco para quem usa o painel. */
export function peopleToolError(code?:string){
 if(code==='42501')return{status:403,error:'Você não tem permissão para esta ação nesta igreja.'};
 if(code==='55000')return{status:409,error:'As duas pessoas usam o aplicativo. Remova o acesso de uma delas antes de unificar.'};
 if(code==='22023')return{status:400,error:'Revise os dados informados.'};
 if(code==='40001')return{status:409,error:'Os dados mudaram enquanto você editava. Atualize e tente de novo.'};
 return{status:503,error:'Não foi possível concluir agora. Tente de novo.'};
}

// ── Exportação ──────────────────────────────────────────────────────────────────────────────────────
export type ExportPerson={code?:string|null;name:string;email:string;phone:string;status:string;group:string;birthDate:string;gender:string;maritalStatus:string;
 baptized:string;baptismDate:string;tags:string;since:string;campus:string;address:string;number:string;district:string;city:string;state:string;zip:string};
export const exportColumns=[['code','Nº',10],['name','Nome',32],['email','E-mail',30],['phone','Celular',18],['status','Etapa',16],['group','Grupo',20],
 ['birthDate','Nascimento',13],['gender','Gênero',12],['maritalStatus','Estado civil',14],['baptized','Batizado',10],['baptismDate','Batismo',13],
 ['tags','Marcadores',24],['since','Desde',14],['campus','Igreja',20],['address','Endereço',30],['number','Número',9],['district','Bairro',18],
 ['city','Cidade',18],['state','UF',6],['zip','CEP',11]] as const;
/** Texto que começa com =, +, - ou @ vira texto puro, para a planilha não ler como fórmula. */
export const safeCell=(v:unknown)=>{const s=v==null?'':String(v);return /^[=+\-@\t\r]/.test(s)?"'"+s:s};
const br=(d:string)=>/^\d{4}-\d{2}-\d{2}$/.test(d)?d.slice(8,10)+'/'+d.slice(5,7)+'/'+d.slice(0,4):d;
export function exportRow(p:ExportPerson){
 const row:Record<string,string>={};
 for(const [key] of exportColumns){const v=(p as unknown as Record<string,unknown>)[key];row[key]=safeCell(key==='birthDate'||key==='baptismDate'?br(String(v||'')):v)}
 return row;
}
export function exportFileName(today=new Date()){return 'pessoas-'+today.toISOString().slice(0,10)+'.xlsx'}

/** Junta datas do histórico por mês para exibir em blocos ("novembro de 2026"). */
export function timelineGroups<T extends {at:string}>(events:T[]){
 const out:{label:string;items:T[]}[]=[];
 for(const e of events){
  const d=new Date(e.at.length===10?e.at+'T12:00:00Z':e.at);
  const label=isNaN(d.getTime())?'Sem data':d.toLocaleDateString('pt-BR',{month:'long',year:'numeric',timeZone:'America/Sao_Paulo'});
  const last=out[out.length-1];if(last&&last.label===label)last.items.push(e);else out.push({label,items:[e]});
 }
 return out;
}
export function eventDate(at:string){
 const d=new Date(at.length===10?at+'T12:00:00Z':at);if(isNaN(d.getTime()))return '';
 return at.length===10?d.toLocaleDateString('pt-BR',{day:'2-digit',month:'2-digit',year:'numeric',timeZone:'UTC'})
  :d.toLocaleString('pt-BR',{day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit',timeZone:'America/Sao_Paulo'});
}
