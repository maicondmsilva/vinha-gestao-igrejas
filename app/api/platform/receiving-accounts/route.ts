import {centralRoute,rpc,OperationError} from '../../../lib/supabase/operations';
import {boundedBody} from '../../../lib/private-files';
import {receiverId} from '../../../lib/finance-receivers';
export const GET=centralRoute(async(_r,client)=>rpc(client,'finance_receiver_settings',{p_org:null,p_unit:null,p_action:'central',p_data:{}}));
export const POST=centralRoute(async(r,client,session)=>{
 if(!['owner','admin'].includes(session.role))throw new OperationError('Sem permissão para bloquear conexões.',403);
 const d=JSON.parse(new TextDecoder().decode(await boundedBody(r,16384))) as Record<string,unknown>;
 if(!['central_hold','central_resume'].includes(String(d.action))||!Number.isSafeInteger(d.version)||Number(d.version)<1||typeof d.reason!=='string'||d.reason.trim().length<5||d.reason.length>300||Object.keys(d).some(k=>!['id','org','unit','action','version','reason'].includes(k)))throw new OperationError('Revise a solicitação.');
 return rpc(client,'finance_receiver_settings',{p_org:receiverId(d.org),p_unit:receiverId(d.unit),p_action:d.action,p_data:{id:receiverId(d.id),version:d.version,reason:d.reason.trim()}});
});
