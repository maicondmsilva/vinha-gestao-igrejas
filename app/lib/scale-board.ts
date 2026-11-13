// Escalas · quadro de montagem: validação dos pedidos, rótulos e mensagens.
import {uuidPattern} from './private-files.ts';

const id=(v:unknown):v is string=>typeof v==='string'&&uuidPattern.test(v);
const day=(v:unknown):v is string=>typeof v==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(v)&&!Number.isNaN(Date.parse(v+'T00:00:00Z'));
const fail=():never=>{throw Error('Revise os dados do quadro.')};

export const conflictLabels:Record<string,string>={unavailable:'Indisponível',availability:'Fora da disponibilidade',qualification:'Sem a função',duplicate:'Já escalado no culto',overlap:'Escalado em outro horário'};
export const conflictLabel=(c:string)=>conflictLabels[c]||'Conflito';

export function weekRange(from:string,days:number){const d=new Date(from+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+days-1);return{from,to:d.toISOString().slice(0,10)}}

export function boardQuery(request:Request){
 const q=new URL(request.url).searchParams;
 for(const k of q.keys())if(!['unit','from','to','team','tenant'].includes(k)||q.getAll(k).length!==1)fail();
 const unit=q.get('unit'),from=q.get('from'),to=q.get('to'),team=q.get('team');
 if(!id(unit)||!day(from)||!day(to)||team&&!id(team))fail();
 const span=(Date.parse(to!)-Date.parse(from!))/86400000;if(span<0||span>62)fail();
 return{unit:unit!,data:{from:from!,to:to!,...(team?{team}:{})}};
}

export function boardCommand(value:unknown){
 if(!value||typeof value!=='object'||Array.isArray(value))fail();
 const v=value as Record<string,unknown>;if(Object.keys(v).some(k=>!['unit','action','data'].includes(k))||!id(v.unit))fail();
 const d=(v.data&&typeof v.data==='object'&&!Array.isArray(v.data)?v.data:fail()) as Record<string,unknown>;
 if(v.action==='assign'){
  if(Object.keys(d).some(k=>!['service','role','ordinal','member','version','override','reason'].includes(k)))fail();
  if(!id(d.service)||!id(d.role)||!Number.isInteger(d.ordinal)||(d.ordinal as number)<1||!Number.isInteger(d.version)||d.member!==null&&!id(d.member))fail();
  if(d.override!==undefined&&typeof d.override!=='boolean'||d.reason!==undefined&&(typeof d.reason!=='string'||d.reason.length>1000))fail();
  if(d.override===true&&String(d.reason||'').trim().length<10)fail();
  return{unit:v.unit as string,action:'assign',data:d};
 }
 if(v.action==='publish'){
  if(Object.keys(d).some(k=>!['services','override','reason'].includes(k)))fail();
  if(!Array.isArray(d.services)||!d.services.length||d.services.length>31||!d.services.every(id))fail();
  if(d.override!==undefined&&typeof d.override!=='boolean'||d.reason!==undefined&&(typeof d.reason!=='string'||d.reason.length>1000))fail();
  if(d.override===true&&String(d.reason||'').trim().length<10)fail();
  return{unit:v.unit as string,action:'publish',data:d};
 }
 return fail();
}

type Batch={published:string[];failed:{id:string;code:string;error:string}[]};
export function boardPublishMessage(r:Batch){
 const n=r.published.length,parts=[n===1?'1 escala publicada.':n+' escalas publicadas.'];
 const conflict=r.failed.filter(f=>/scale_conflict/.test(f.error)).length,other=r.failed.length-conflict;
 if(conflict)parts.push(conflict+' com conflito: confirme com uma justificativa para publicar mesmo assim.');
 if(other)parts.push(other+(other===1?' não pôde ser publicada':' não puderam ser publicadas')+' (vaga sem a função, horário já passou ou sem permissão).');
 return parts.join(' ');
}

// Cor fixa por equipe (mesma equipe, mesma cor em todo o calendário), com bom contraste sobre fundo claro.
export const teamPalette=['#2f6f4f','#2b5f9e','#8a4fb3','#b5651d','#a23a5a','#1f7a7a','#6b6f1e','#5a4fcf'];
export function teamColor(id:string){let h=0;for(const c of id)h=(h*31+c.charCodeAt(0))>>>0;return teamPalette[h%teamPalette.length]}
