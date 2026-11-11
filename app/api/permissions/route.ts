import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedBody} from '../../lib/private-files';
import {permissionCommand} from '../../lib/permissions';
import {uuidPattern} from '../../lib/private-files';

const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
const reasons:Record<string,string>={permission_admin_denied:'Somente o dono e administradores alteram permissões. Usuários e permissões só o dono concede.',owner_has_all_permissions:'O dono já tem todas as permissões.',invalid_actions:'Escolha ações disponíveis nesta seção.',invalid_groups:'Esta seção não aceita limite por grupos.',invalid_unit:'Igreja inválida.',invalid_template:'Modelo inválido.',membership_not_found:'Usuário não encontrado.'};

/** Configurações › Usuários e permissões. The database decides who may read and change grants. */
async function run(r:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(r,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);const a=auth.access!;
 let action:string,data:Record<string,unknown>;
 try{
  if(write){const c=permissionCommand(JSON.parse(new TextDecoder().decode(await boundedBody(r,8192))));action=c.action;data=c.data}
  else{const p=new URL(r.url).searchParams;if([...p.keys()].some(k=>!['membership','tenant'].includes(k)||p.getAll(k).length!==1))throw Error('Filtro inválido.');const m=p.get('membership')||'';if(m&&!uuidPattern.test(m))throw Error('Usuário inválido.');action=m?'list':'catalog';data=m?{membership:m}:{}}
 }catch(e){return json({error:e instanceof Error?e.message:'Dados inválidos.'},400)}
 const res=await (a.client as unknown as OperationsClient).rpc('permission_admin',{p_org:a.membership.organization_id,p_action:action,p_data:data});
 if(res.error){const key=(res.error.message||'').trim(),code=res.error.code;return json({error:reasons[key]||(code==='42501'?'Sem permissão para alterar acessos.':'Não foi possível salvar. Atualize e tente de novo.')},code==='42501'?403:code==='22023'?400:503)}
 return json(res.data);
}
export const GET=(r:Request)=>run(r,false);
export const POST=(r:Request)=>run(r,true);
