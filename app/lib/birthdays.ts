// Pessoas · aniversariantes: validação da consulta, mensagem de parabéns e link do WhatsApp.
import {uuidPattern} from './private-files.ts';

export type BirthdayItem={person:string;name:string;kind:'birthday'|'wedding';date:string;years:number;phone:string|null;journey:string|null};
export const ranges=[['today','Hoje'],['week','Próximos 7 dias'],['month','Este mês']] as const;

export function birthdaysQuery(request:Request){
 const q=new URL(request.url).searchParams;const unit=q.get('unit'),range=q.get('range')||'today';
 if(!unit||!uuidPattern.test(unit)||!ranges.some(([r])=>r===range))throw Error('Revise a igreja e o período.');
 return{unit,range};
}

const first=(name:string)=>name.trim().split(/\s+/)[0]||name;
export function birthdayMessage(i:Pick<BirthdayItem,'name'|'kind'|'years'>,church:string){
 return i.kind==='wedding'
  ?`Parabéns, ${first(i.name)}! A ${church} celebra com vocês os ${i.years} anos de casamento. Deus abençoe a família!`
  :`Feliz aniversário, ${first(i.name)}! A ${church} celebra a sua vida e ora por você. Deus abençoe seus ${i.years} anos!`;
}

/** Link do WhatsApp com a mensagem pronta. Número brasileiro: acrescenta 55 quando falta. */
export function whatsappLink(phone:string|null,text:string){
 let d=(phone||'').replace(/\D/g,'');
 if(d.length===10||d.length===11)d='55'+d;
 if(!/^55\d{10,11}$/.test(d))return null;
 return 'https://wa.me/'+d+'?text='+encodeURIComponent(text);
}

export function dayLabel(date:string,today:string){
 if(date===today)return 'Hoje';
 const t=new Date(today+'T12:00:00Z');t.setUTCDate(t.getUTCDate()+1);
 if(date===t.toISOString().slice(0,10))return 'Amanhã';
 const d=new Date(date+'T12:00:00Z');
 return d.toLocaleDateString('pt-BR',{weekday:'short',day:'2-digit',month:'2-digit',timeZone:'UTC'});
}
