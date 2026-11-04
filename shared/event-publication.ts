import type {EventInfo} from './event-info';
import {mediaHttps} from './ministry-media.ts';
export function eventPublicationIssues(event:{starts_at:string;status:string},info:EventInfo|null|undefined,now=Date.now()):string[]{
 const issues:string[]=[];
 if(event.status==='cancelled')issues.push('Este evento está cancelado.');
 if(!Number.isFinite(Date.parse(event.starts_at))||Date.parse(event.starts_at)<=now)issues.push('Ajuste o início para uma data e um horário futuros.');
 if(info){const v=info.venue;if(v.format!=='online'&&[v.street,v.number,v.city,v.state].some(s=>!s.trim()))issues.push('Complete rua, número, cidade e estado do local.');if(v.format!=='presential'&&!mediaHttps(v.onlineUrl.trim()))issues.push('Informe um link HTTPS válido de participação online.');}
 return issues;
}
