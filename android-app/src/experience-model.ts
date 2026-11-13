import type {PublicPost} from '../../shared/member-church';
export type MainTab='content'|'agenda'|'home'|'contribute'|'more';
export const mainTabs=[{id:'home',label:'Início',icon:'home'},{id:'agenda',label:'Agenda',icon:'calendar'},{id:'content',label:'Mensagens',icon:'play'},{id:'contribute',label:'Contribuir',icon:'give'},{id:'more',label:'Menu',icon:'menu'}] as const;
export const postKinds:Record<string,string>={notice:'Aviso',event:'Agenda',video:'Vídeo',service:'Culto'};
const normalized=(text:string)=>text.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('pt-BR');
export function publicationList(posts:PublicPost[],section:'content'|'agenda'|'all',query='',kind='all'){
 const search=normalized(query.trim());
 return posts.filter(p=>['notice','event','video','service'].includes(p.kind)&&(section==='all'||(section==='agenda'?['event','service']:['notice','video']).includes(p.kind))&&(kind==='all'||p.kind===kind)&&(!search||normalized(p.title+' '+p.body).includes(search)));
}
export function firstName(value?:string){return value?.trim().split(/\s+/)[0]||'visitante'}
export function brandColor(value:string){return /^#[0-9a-f]{6}$/i.test(value)?value:'#087FA3'}
export function onBrand(value:string){const c=brandColor(value),parts=[1,3,5].map(i=>parseInt(c.slice(i,i+2),16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);return .2126*parts[0]+.7152*parts[1]+.0722*parts[2]>.179?'#081820':'#ffffff'}

/** Cor de destaque legível sobre o fundo do tema: clareia no escuro e escurece no claro quando a cor da igreja tem pouco contraste. */
export function accentOn(brand:string,dark:boolean){const c=brandColor(brand),mix=(t:number,to:number)=>'#'+[1,3,5].map(i=>Math.round(parseInt(c.slice(i,i+2),16)+(to-parseInt(c.slice(i,i+2),16))*t).toString(16).padStart(2,'0')).join('');
 const lum=(h:string)=>{const v=[1,3,5].map(i=>parseInt(h.slice(i,i+2),16)/255).map(x=>x<=.04045?x/12.92:((x+.055)/1.055)**2.4);return .2126*v[0]+.7152*v[1]+.0722*v[2]};
 const l=lum(c);if(dark)return l<.25?mix(.5,255):c;return l>.45?mix(.45,0):c}
