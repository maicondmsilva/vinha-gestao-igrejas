import {NextResponse} from 'next/server';
import {parseAccessContext,type AccessMembership} from './access';
import type {Json} from './database.types';
import {createSupabaseRequestClient,supabaseServerConfigured} from './request';

const permissions:Record<string,string[]>={
 owner:['*'],
 pastor:['people.read','people.write','units.read','units.manage','audit.read'],
 admin:['*'],
 secretary:['people.read','people.write','units.read'],
 finance:['units.read'],
 leader:['people.read','people.write','units.read'],
 member:['people.self','units.read'],
 viewer:['units.read'],
};

export type SupabaseChurchAccess={
 client:ReturnType<typeof createSupabaseRequestClient>;
 userId:string;
 email:string;
 membership:AccessMembership;
 can:(permission:string)=>boolean;
};

export async function authorizeSupabaseChurch(request:Request,permission:string){
 if(!supabaseServerConfigured)return null;
 const client=createSupabaseRequestClient(request);
 const {data:{user},error:userError}=await client.auth.getUser();
 if(userError||!user)return{access:null,response:NextResponse.json({error:'Autenticação necessária.'},{status:401})};
 const {data,error}=await client.rpc('access_context');
 if(error)return{access:null,response:NextResponse.json({error:'Não foi possível validar seu acesso.'},{status:503})};
 const context=parseAccessContext(data);
 const url=new URL(request.url),hint=request.headers.get('x-vinha-tenant')||url.searchParams.get('tenant')||'';
 const preferred=context.preference.selected_organization_id||'';
 const membership=context.memberships.find(item=>item.organization_slug===hint||item.organization_id===hint)
  ||context.memberships.find(item=>item.organization_id===preferred)
  ||context.memberships[0];
 if(!membership)return{access:null,response:NextResponse.json({error:'Nenhuma organização ativa foi encontrada para este usuário.'},{status:403})};
 const grants=permissions[membership.role]||[];
 const can=(value:string)=>grants.includes('*')||grants.includes(value);
 if(!can(permission))return{access:null,response:NextResponse.json({error:'Você não possui permissão para esta ação.'},{status:403})};
 return{access:{client,userId:user.id,email:user.email||context.email||'',membership,can} satisfies SupabaseChurchAccess,response:null};
}

export async function supabaseAudit(request:Request,access:SupabaseChurchAccess,action:string,entityType:string,entityId?:string,metadata:Record<string,unknown>={}){
 const {error}=await access.client.from('audit_logs').insert({
  organization_id:access.membership.organization_id,
  actor_user_id:access.userId,
  action,
  entity_type:entityType,
  entity_id:entityId||null,
  metadata:metadata as Json,
  ip_address:request.headers.get('cf-connecting-ip')||request.headers.get('x-forwarded-for')?.split(',')[0]?.trim()||null,
 });
 if(error)console.error('Falha ao registrar auditoria no Supabase',error.message);
}
