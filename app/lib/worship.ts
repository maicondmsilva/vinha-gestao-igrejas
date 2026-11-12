// Louvor: validação dos pedidos da tela, mensagens de erro e transposição de cifras.
import {uuidPattern} from './private-files.ts';

const id=(v:unknown)=>typeof v==='string'&&uuidPattern.test(v);
export const worshipKeys=['C','C#','Db','D','D#','Eb','E','F','F#','Gb','G','G#','Ab','A','A#','Bb','B'] as const;
/** Tons oferecidos nas listas (um nome por nota), maiores e menores. */
export const keyOptions=['C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B','Cm','C#m','Dm','Ebm','Em','Fm','F#m','Gm','G#m','Am','Bbm','Bm'];
export const songStatus=[['active','Ativa'],['rehearsal','Em ensaio'],['archived','Arquivada']] as const;
export const timeSignatures=['','2/4','3/4','4/4','6/8','12/8'] as const;
const keyRe=/^([A-G](#|b)?m?)?$/;

// ---------- Transposição ----------
const sharp=['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
const flat=['C','Db','D','Eb','E','F','Gb','G','Ab','A','Bb','B'];
const index=(note:string)=>{const i=sharp.indexOf(note);return i>=0?i:flat.indexOf(note)};
/** Tons que se escrevem com bemóis (escolha da grafia ao transpor). */
const flatKeys=new Set(['F','Bb','Eb','Ab','Db','Gb','Dm','Gm','Cm','Fm','Bbm','Ebm']);
/** Semitons entre dois tons (0 a 11). Tom vazio ou inválido = 0. */
export function semitones(from:string,to:string){
 const a=index((from.match(/^[A-G](#|b)?/)||[''])[0]),b=index((to.match(/^[A-G](#|b)?/)||[''])[0]);
 return a<0||b<0?0:(b-a+12)%12;
}
function moveNote(note:string,steps:number,useFlats:boolean){const i=index(note);if(i<0)return note;const n=(i+steps+120)%12;return (useFlats?flat:sharp)[n]}
/** Transpõe um acorde (ex.: "F#m7/C#") mantendo a qualidade e o baixo. */
export function transposeChord(chord:string,steps:number,useFlats=false){
 if(!steps)return chord;
 return chord.replace(/^([A-G](?:#|b)?)([^/]*)(?:\/([A-G](?:#|b)?))?$/,(_m,root:string,rest:string,bass?:string)=>moveNote(root,steps,useFlats)+rest+(bass?'/'+moveNote(bass,steps,useFlats):''));
}
/** Transpõe todos os acordes entre colchetes de uma cifra: "[G]Santo [D/F#]santo". */
export function transposeChart(chart:string,from:string,to:string){
 const steps=semitones(from,to),useFlats=flatKeys.has(to);
 return steps?chart.replace(/\[([^\]\s]{1,12})\]/g,(_m,c:string)=>'['+transposeChord(c,steps,useFlats)+']'):chart;
}
/** Divide uma linha de cifra em pares acorde + texto, para desenhar o acorde acima da letra. */
export function chartLine(line:string){
 const parts:{chord:string;text:string}[]=[];let rest=line;const first=rest.indexOf('[');
 if(first!==0){parts.push({chord:'',text:first<0?rest:rest.slice(0,first)});if(first<0)return parts;rest=rest.slice(first)}
 for(const m of rest.matchAll(/\[([^\]]*)\]([^[]*)/g))parts.push({chord:m[1],text:m[2]});
 return parts;
}

// ---------- Pedidos ----------
type Body=Record<string,unknown>;
const str=(v:unknown,max:number,min=0)=>typeof v==='string'&&v.trim().length>=min&&v.length<=max;
const isObj=(v:unknown):v is Body=>!!v&&typeof v==='object'&&!Array.isArray(v);

export function worshipQuery(request:Request){
 const p=new URL(request.url).searchParams;
 for(const k of p.keys())if(!['unit','kind','search','status','tag','key','page','id','service','from','to','tenant'].includes(k)||p.getAll(k).length!==1)throw Error('Filtro inválido ou repetido.');
 const unit=p.get('unit'),kind=p.get('kind')||'songs';
 if(!id(unit)||!['songs','song','services','setlist'].includes(kind))throw Error('Selecione a igreja e revise os filtros.');
 const page=Number(p.get('page')||1),search=p.get('search')||'',status=p.get('status')||'',tag=p.get('tag')||'',key=p.get('key')||'';
 if(!Number.isInteger(page)||page<1||page>1000||search.length>100||!['','current','all','active','rehearsal','archived'].includes(status)||tag.length>30||!keyRe.test(key))throw Error('Revise os filtros.');
 if(kind==='song'&&!id(p.get('id'))||kind==='setlist'&&!id(p.get('service')))throw Error('Item inválido.');
 const date=(v:string|null)=>!v||/^\d{4}-\d{2}-\d{2}$/.test(v);
 if(!date(p.get('from'))||!date(p.get('to')))throw Error('Período inválido.');
 return kind==='songs'?{unit:unit!,fn:'worship_songs',action:'list',data:{search,status,tag,key,page}}
  :kind==='song'?{unit:unit!,fn:'worship_songs',action:'detail',data:{id:p.get('id')}}
  :kind==='services'?{unit:unit!,fn:'worship_setlists',action:'services',data:{from:p.get('from')||'',to:p.get('to')||''}}
  :{unit:unit!,fn:'worship_setlists',action:'get',data:{service:p.get('service')}};
}

export function worshipCommand(value:unknown){
 if(!isObj(value)||Object.keys(value).some(k=>!['unit','kind','action','data'].includes(k))||!id(value.unit)||!isObj(value.data))throw Error('Pedido inválido.');
 const d=value.data,kind=value.kind,action=value.action;
 if(kind==='song'){
  if(!['save','delete'].includes(String(action))||!id(d.id)||!Number.isInteger(d.version)||Number(d.version)<0)throw Error('Atualize a música e tente de novo.');
  if(action==='delete'){if(Object.keys(d).some(k=>!['id','version'].includes(k)))throw Error('Pedido inválido.');return{unit:value.unit as string,fn:'worship_songs',action:'delete',data:d}}
  const allowed=['id','version','title','artist','originalKey','bpm','timeSignature','chart','links','tags','status','notes'];
  if(Object.keys(d).some(k=>!allowed.includes(k)))throw Error('Pedido inválido.');
  if(!str(d.title,160,1))throw Error('Informe o nome da música.');
  if(!str(d.artist??'',160)||!str(d.chart??'',20000)||!str(d.notes??'',1000))throw Error('Texto muito longo.');
  if(!keyRe.test(String(d.originalKey??'')))throw Error('Tom inválido.');
  if(d.bpm!==undefined&&d.bpm!==''&&(!Number.isInteger(Number(d.bpm))||Number(d.bpm)<20||Number(d.bpm)>300))throw Error('BPM deve estar entre 20 e 300.');
  if(!timeSignatures.includes(String(d.timeSignature??'') as typeof timeSignatures[number]))throw Error('Compasso inválido.');
  if(!songStatus.some(([s])=>s===(d.status??'active')))throw Error('Situação inválida.');
  if(d.tags!==undefined&&(!Array.isArray(d.tags)||d.tags.length>12||d.tags.some(t=>!str(t,30,1))))throw Error('Use até 12 etiquetas curtas.');
  if(d.links!==undefined){if(!isObj(d.links)||Object.keys(d.links).some(k=>!['video','audio','chart'].includes(k))||Object.values(d.links).some(v=>typeof v!=='string'||v.length>500||v!==''&&!/^https:\/\/[^\s]+$/.test(v)))throw Error('Links devem começar com https://');}
  return{unit:value.unit as string,fn:'worship_songs',action:'save',data:{...d,bpm:d.bpm===undefined||d.bpm===''?'':String(d.bpm)}};
 }
 if(kind==='setlist'){
  if(!['save','publish','unpublish'].includes(String(action))||!id(d.service)||!Number.isInteger(d.version)||Number(d.version)<0)throw Error('Atualize o repertório e tente de novo.');
  if(action!=='save'){if(Object.keys(d).some(k=>!['service','version'].includes(k)))throw Error('Pedido inválido.');return{unit:value.unit as string,fn:'worship_setlists',action:String(action),data:d}}
  if(Object.keys(d).some(k=>!['service','version','notes','items','keepPublished'].includes(k))||!str(d.notes??'',2000)||!Array.isArray(d.items)||d.items.length>40)throw Error('Revise o repertório (até 40 músicas).');
  for(const it of d.items){if(!isObj(it)||Object.keys(it).some(k=>!['song','key','minister','notes'].includes(k))||!id(it.song)||!keyRe.test(String(it.key??''))||(it.minister!==undefined&&it.minister!==''&&!id(it.minister))||!str(it.notes??'',500))throw Error('Revise as músicas do repertório.')}
  return{unit:value.unit as string,fn:'worship_setlists',action:'save',data:d};
 }
 throw Error('Pedido inválido.');
}

export function worshipFailure(code?:string,message=''){
 const known:Record<string,string>={worship_access_denied:'Você não tem permissão para esta ação no Louvor.',song_version_conflict:'A música foi alterada por outra pessoa. Atualize e tente de novo.',
  song_in_use:'Esta música já foi usada em cultos. Em vez de excluir, arquive.',setlist_version_conflict:'O repertório foi alterado por outra pessoa. Atualize e tente de novo.',
  invalid_setlist_song:'Uma das músicas não está no repertório desta igreja ou foi arquivada.',invalid_setlist_minister:'O ministro escolhido não é uma pessoa desta igreja.',
  setlist_empty:'Adicione ao menos uma música antes de publicar.',service_cancelled:'Este culto foi cancelado.',service_not_found:'Culto não encontrado nesta igreja.',
  song_not_found:'Música não encontrada nesta igreja.',setlist_not_found:'Monte e salve o repertório antes de publicar.'};
 for(const [k,v] of Object.entries(known))if(message.includes(k))return{status:k.includes('conflict')?409:k.includes('denied')||k.includes('not_found')?403:400,error:v};
 if(code==='23505')return{status:409,error:'Já existe uma música com este nome e artista.'};
 if(code==='23514'||code==='22023')return{status:400,error:'Revise os campos da música.'};
 if(code==='42501')return{status:403,error:'Este módulo não está liberado para você nesta igreja.'};
 return{status:503,error:'Não foi possível concluir. Atualize e tente de novo.'};
}
