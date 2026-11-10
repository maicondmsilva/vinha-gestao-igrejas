import {uuidPattern} from './private-files.ts';
const uuid=(v:unknown)=>typeof v==='string'&&uuidPattern.test(v);
const local=(v:unknown)=>typeof v==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(v)&&!Number.isNaN(Date.parse(v+'Z'));
export function planningInput(value:unknown,write:boolean){
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('Solicitação inválida.');
 const b=value as Record<string,unknown>,d=b.data as Record<string,unknown>;
 if(Object.keys(b).some(k=>!['unit','action','data'].includes(k))||!uuid(b.unit)||!d||typeof d!=='object'||Array.isArray(d)||!['list','choices','detail',...(write?['preview','save','duplicate','cancel']:[])].includes(String(b.action)))throw Error('Selecione a igreja e a operação.');
 if(Object.keys(d).some(k=>!['id','team','search','page','from','to','status','scope','operation','title','event','location','notes','coordinator','startsLocal','arrivalLocal','endsLocal','positions','repeat','count','request','token'].includes(k)))throw Error('Campo desconhecido no planejamento.');
 for(const k of ['id','team','event','coordinator','request'])if(d[k]&&!uuid(d[k]))throw Error('Selecione um cadastro válido.');
 if(d.search!==undefined&&(typeof d.search!=='string'||d.search.length>100)||d.page!==undefined&&(!Number.isInteger(d.page)||Number(d.page)<1||Number(d.page)>10000))throw Error('Revise os filtros.');
 if(['save','duplicate','cancel'].includes(String(b.action))&&(!uuid(d.request)||typeof d.token!=='string'||!/^[a-f0-9]{32}$/.test(d.token)))throw Error('Confira a prévia antes de salvar.');
 if(['save','duplicate','preview'].includes(String(b.action))&&d.operation!=='cancel'){
  if(typeof d.title!=='string'||d.title.trim().length<2||d.title.length>160)throw Error('Informe o título, entre 2 e 160 caracteres.');
  if(!local(d.arrivalLocal)||!local(d.startsLocal)||!local(d.endsLocal)||String(d.arrivalLocal)>String(d.startsLocal)||String(d.endsLocal)<=String(d.startsLocal))throw Error('A chegada deve ser antes ou no início; o término deve ser depois do início.');
  if(typeof d.location!=='string'||d.location.length>300||typeof d.notes!=='string'||d.notes.length>2000)throw Error('Use até 300 caracteres no local e 2.000 nas orientações.');
  if(!Array.isArray(d.positions)||d.positions.length<1||d.positions.length>500||d.positions.some(p=>!p||typeof p!=='object'||!uuid(p.team)||!uuid(p.role)||!Number.isInteger(p.ordinal)||p.ordinal<1||p.ordinal>100||p.member&&!uuid(p.member)))throw Error('Adicione ao menos uma equipe e suas vagas.');
 }
 return {unit:b.unit as string,action:b.action as string,data:d};
}
export function planningError(code?:string,message?:string){
 const errors:Record<string,string>={scale_dates:'Revise chegada, início e término. A escala pode durar até 7 dias e começar até 2 anos à frente.',scale_positions:'Adicione ao menos uma vaga. Não repita a mesma vaga da função.',scale_person_duplicate:'Uma pessoa foi escolhida em mais de uma vaga. Mantenha apenas uma atribuição nesta escala.',scale_event_invalid:'O evento não está disponível nesta igreja. Busque outro ou remova o vínculo.',scale_person_invalid:'A pessoa deve estar ativa nesta igreja e na equipe escolhida.',scale_role_invalid:'Uma função ou equipe foi desativada. Atualize as vagas antes de salvar.',scale_recurrence:'Escolha até 120 ocorrências, dentro dos próximos 2 anos.',scale_locked:'A série inclui uma escala cancelada. Edite somente uma ocorrência em rascunho.',scale_period:'Escolha um período de até 366 dias, com o fim depois do início.'};
 return {status:code==='42501'?403:code==='40001'?409:['22023','22P02','23514','23503','23502','22007','22008'].includes(code||'')?400:503,error:code==='42501'?'Você não tem permissão para todas as equipes ou para esta operação.':code==='40001'?'Uma ocorrência ou permissão mudou. Atualize a prévia antes de salvar.':errors[message||'']||'Não foi possível concluir. Atualize a consulta e confira os campos antes de repetir.'};
}
