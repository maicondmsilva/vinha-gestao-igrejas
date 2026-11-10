import {mediaHttps} from './ministry-media.ts';
export function canonicalEventPath(path:string){return /^\/eventos\/e-[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}(\/equipe)?\/?$/i.test(path)}
export type EventVenue={format:'presential'|'online'|'hybrid';church:string;postal_code:string;street:string;number:string;complement:string;district:string;city:string;state:string;onlineUrl:string};
export type EventActivity={id:string;title:string;starts:string;ends:string;location:string};
export type EventGuest={id:string;name:string;role:string;bio:string;url:string;photo:string};
export type EventInfo={venue:EventVenue;scope:'local'|'selected'|'all'|'group';targets:string[];group:string;groupVersion:number;schedule:EventActivity[];guests:EventGuest[];contacts:{phone:string;whatsapp:string;email:string;instagram:string;facebook:string;youtube:string;website:string};gallery:{id:string;url:string;caption:string}[];team:string[]};
export const emptyEventInfo=():EventInfo=>({venue:{format:'presential',church:'',postal_code:'',street:'',number:'',complement:'',district:'',city:'',state:'',onlineUrl:''},scope:'local',targets:[],group:'',groupVersion:0,schedule:[],guests:[],contacts:{phone:'',whatsapp:'',email:'',instagram:'',facebook:'',youtube:'',website:''},gallery:[],team:[]});
const uuid=(v:unknown)=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v);
const object=(v:unknown,keys:string[])=>!!v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).sort().join(',')===keys.sort().join(',');
const text=(v:unknown,n:number)=>typeof v==='string'&&v.length<=n&&!/[\u0000-\u0008]/.test(v);
export const eventImageUrl=(v:unknown)=>typeof v==='string'&&(/^\/api\/event-images\/[0-9a-f-]{36}$/.test(v)||!!mediaHttps(v));
const link=(v:unknown)=>v===''||!!mediaHttps(v);
export function eventInfoValid(v:unknown):v is EventInfo{if(!object(v,['venue','scope','targets','group','groupVersion','schedule','guests','contacts','gallery','team']))return false;const x=v as EventInfo,z=x.venue;
 if(!object(z,Object.keys(emptyEventInfo().venue))||!['presential','online','hybrid'].includes(z.format)||!Object.values(z).every(v=>text(v,2000))||!link(z.onlineUrl)||z.church!==''&&!uuid(z.church)||z.postal_code!==''&&!/^\d{5}-?\d{3}$/.test(z.postal_code)||z.state!==''&&!/^[A-Z]{2}$/.test(z.state))return false;
 if(!['local','selected','all','group'].includes(x.scope)||!Array.isArray(x.targets)||x.targets.length>200||!x.targets.every(uuid)||new Set(x.targets).size!==x.targets.length||x.group!==''&&!uuid(x.group)||!Number.isInteger(x.groupVersion)||x.groupVersion<0)return false;
 if(!Array.isArray(x.schedule)||x.schedule.length>100||!x.schedule.every(a=>object(a,['id','title','starts','ends','location'])&&uuid(a.id)&&text(a.title,160)&&a.title.trim().length>1&&text(a.location,160)&&typeof a.starts==='string'&&typeof a.ends==='string'&&Number.isFinite(Date.parse(a.starts))&&Date.parse(a.ends)>Date.parse(a.starts)))return false;
 if(!Array.isArray(x.guests)||x.guests.length>40||!x.guests.every(g=>object(g,['id','name','role','bio','url','photo'])&&uuid(g.id)&&text(g.name,160)&&g.name.trim().length>1&&text(g.role,160)&&text(g.bio,3000)&&link(g.url)&&(g.photo===''||eventImageUrl(g.photo))))return false;
 if(!object(x.contacts,Object.keys(emptyEventInfo().contacts))||!Object.values(x.contacts).every(v=>text(v,2000))||x.contacts.email!==''&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(x.contacts.email)||!['instagram','facebook','youtube','website'].every(k=>link(x.contacts[k as keyof typeof x.contacts])))return false;
 return Array.isArray(x.gallery)&&x.gallery.length<=30&&x.gallery.every(g=>object(g,['id','url','caption'])&&uuid(g.id)&&eventImageUrl(g.url)&&text(g.caption,200))&&Array.isArray(x.team)&&x.team.length<=30&&x.team.every(uuid)&&new Set(x.team).size===x.team.length;
}
export function venueAddress(z:EventVenue){return [z.street,z.number,z.complement,z.district,z.city,z.state,z.postal_code].filter(Boolean).join(', ')}
