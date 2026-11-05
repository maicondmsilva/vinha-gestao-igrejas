import {trustedSessionRequest} from '../../lib/access-security';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
export const GET=(r:Request)=>run(r,false);export const POST=(r:Request)=>run(r,true);
async function run(request:Request,write:boolean){try{
 if(write&&!trustedSessionRequest(request))return json({error:'Origem não autorizada.'},403);
 const b=write?JSON.parse(new TextDecoder().decode(await boundedBody(request,8000))):Object.fromEntries(new URL(request.url).searchParams);
 if(!b||Object.keys(b).some(k=>!['event','stars','comment'].includes(k))||!uuidPattern.test(b.event)||write&&(!Number.isInteger(b.stars)||b.stars<1||b.stars>5||typeof b.comment!=='string'||b.comment.length>1500))return json({error:'Confira a avaliação.'},400);
 const r=await db(request).rpc('member_event_experience',{p_event:b.event,p_stars:write?b.stars:null,p_comment:write?b.comment:''});
 if(r.error)return json({error:'A avaliação exige participação confirmada, conta autenticada e evento encerrado.'},403);
 return json(r.data||{},r.data?200:404);
}catch{return json({error:'Não foi possível consultar a experiência.'},503)}}
