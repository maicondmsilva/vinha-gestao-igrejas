import type {PublicPost} from '../../shared/member-church';
export type MainTab='content'|'agenda'|'home'|'contribute'|'more';
export const mainTabs=[{id:'content',label:'Conteúdos',icon:'▷'},{id:'agenda',label:'Agenda',icon:'▦'},{id:'home',label:'Início',icon:'⌂'},{id:'contribute',label:'Contribua',icon:'♡'},{id:'more',label:'Mais',icon:'☰'}] as const;
export const postKinds:Record<string,string>={notice:'Aviso',event:'Agenda',video:'Vídeo',service:'Culto'};
const normalized=(text:string)=>text.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('pt-BR');
export function publicationList(posts:PublicPost[],section:'content'|'agenda'|'all',query='',kind='all'){
 const search=normalized(query.trim());
 return posts.filter(p=>['notice','event','video','service'].includes(p.kind)&&(section==='all'||(section==='agenda'?['event','service']:['notice','video']).includes(p.kind))&&(kind==='all'||p.kind===kind)&&(!search||normalized(p.title+' '+p.body).includes(search)));
}
export function firstName(value?:string){return value?.trim().split(/\s+/)[0]||'visitante'}
export function brandColor(value:string){return /^#[0-9a-f]{6}$/i.test(value)?value:'#087FA3'}
export function onBrand(value:string){const c=brandColor(value),parts=[1,3,5].map(i=>parseInt(c.slice(i,i+2),16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);return .2126*parts[0]+.7152*parts[1]+.0722*parts[2]>.179?'#081820':'#ffffff'}
