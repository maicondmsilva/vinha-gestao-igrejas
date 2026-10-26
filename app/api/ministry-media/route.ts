import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {mediaSource,mediaHttps} from '../../../shared/ministry-media';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
export async function GET(request:Request){return run(request,false)}
export async function POST(request:Request){return run(request,true)}
async function run(request:Request,write:boolean){try{
 const a=await authorizeSupabaseChurch(request,'units.manage');if(!a||a.response)return a?.response||json({error:'Serviço indisponível.'},503);
 const b=write?JSON.parse(new TextDecoder().decode(await boundedBody(request,16000))):{unit:new URL(request.url).searchParams.get('unit'),action:'list',data:{}};
 if(!b||Object.keys(b).some(k=>!['unit','action','id','version','data'].includes(k))||!uuidPattern.test(b.unit)||!['list','opening','save','publish','archive','live','end'].includes(b.action)||b.id&&!uuidPattern.test(b.id)||!b.data||typeof b.data!=='object'||Array.isArray(b.data))return json({error:'Revise a igreja e os dados da publicação.'},400);
 if(b.action==='save'){const s=mediaSource(b.data.source);if(!s||b.data.poster&&!mediaHttps(b.data.poster)||b.data.download&&!s.downloadable)return json({error:'Use vídeo MP4, transmissão HLS, YouTube ou Vimeo. Download é permitido somente para MP4 autorizado.'},400);b.data.source=s.url}
 if(b.action==='opening'&&b.data.kind!=='none'&&(!mediaHttps(b.data.url)||b.data.kind==='video'&&!mediaSource(b.data.url)?.downloadable))return json({error:'Selecione uma imagem HTTPS ou vídeo MP4 para a abertura.'},400);
 const r=await db(request).rpc('ministry_media_admin',{p_org:a.access!.membership.organization_id,p_unit:b.unit,p_action:b.action,p_id:b.id||null,p_version:b.version??null,p_data:b.data});
 if(r.error)return json({error:r.error.code==='40001'?'A publicação mudou. Atualize antes de salvar novamente.':'Não foi possível confirmar. Confira a igreja, o contrato e os dados.'},r.error.code==='42501'?403:r.error.code==='40001'?409:400);return json(r.data);
 }catch{return json({error:'Conexão interrompida. Atualize a lista antes de repetir.'},503)}}
