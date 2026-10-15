import { trustedSessionRequest, verifiedPlatformIdentity } from '../lib/access-security';
import { env } from 'cloudflare:workers';
import {moduleAllowed} from '../lib/supabase/module-guard';
import type {OperationsClient} from '../lib/supabase/operations';
import {supabaseChurchSession} from '../lib/supabase/church-session';
import { NextResponse } from 'next/server';
import {createSupabaseRequestClient,supabaseServerConfigured} from '../lib/supabase/request';
export type ChurchSession={id:string;churchId:string;churchSlug:string;externalUserId:string;email:string;name:string;role:string;personId:string|null};
export type PlatformSession={id:string;externalUserId:string;email:string;name:string;role:'owner'|'admin'|'support'|'read_only'};
const rolePermissions:Record<string,string[]>={
 admin:['*'],pastor:['people.read','people.write','terms.read','terms.write','kids.read','kids.manage','users.read','audit.read','units.read','units.manage','events.read','events.create','events.publish','cells.read','cells.manage','scales.read','scales.manage'],
 secretary:['people.read','people.write','terms.read','kids.read','kids.checkin','units.read','events.read','events.create','cells.read','scales.read'],kids_leader:['kids.read','kids.manage','people.read','units.read','events.read','cells.read','scales.read'],
 kids_volunteer:['kids.read','kids.checkin'],member:['self.read','children.manage','consents.manage'],responsible:['self.read','children.manage','consents.manage'],
};
export async function sessionFrom(request:Request):Promise<ChurchSession|null>{
 if(!supabaseServerConfigured || !trustedSessionRequest(request))return null;
 try{return await supabaseChurchSession(request)}catch{return null}
}
export async function platformSessionFrom(request:Request):Promise<PlatformSession|null>{
 if(!supabaseServerConfigured || !trustedSessionRequest(request))return null;
 const verified=await verifiedPlatformIdentity(createSupabaseRequestClient(request),request.method);
 if(!verified)return null;
 const {user,operator}=verified;
 return{id:user.id,externalUserId:user.id,email:(user.email||'').toLowerCase(),name:operator.full_name,role:operator.role as PlatformSession['role']};
}
export async function platformAudit(request:Request,session:PlatformSession,action:string,entityType:string,entityId?:string,metadata?:Record<string,unknown>){await env.DB.prepare('INSERT INTO platform_audit_logs (id,actor_platform_user_id,action,entity_type,entity_id,metadata,ip_address,created_at) VALUES (?,?,?,?,?,?,?,?)').bind(crypto.randomUUID(),session.id,action,entityType,entityId||null,metadata?JSON.stringify(metadata):null,request.headers.get('cf-connecting-ip'),Date.now()).run()}
export function can(session:ChurchSession,permission:string){const grants=rolePermissions[session.role]||[];return grants.includes('*')||grants.includes(permission)}
export async function authorize(request:Request,permission:string){const session=await sessionFrom(request);if(!session)return{session:null,response:NextResponse.json({error:'Autenticação necessária.'},{status:401})};if(!can(session,permission))return{session,response:NextResponse.json({error:'Você não possui permissão para esta ação.'},{status:403})};if(supabaseServerConfigured&&!await moduleAllowed(createSupabaseRequestClient(request) as unknown as OperationsClient,session.churchId,permission))return{session,response:NextResponse.json({error:'Módulo bloqueado no contrato desta igreja.'},{status:403})};return{session,response:null}}
export async function unitGrant(session:ChurchSession,unitId:string,roles:string[]){if(['admin','pastor'].includes(session.role))return true;const row=await env.DB.prepare(`WITH RECURSIVE ancestors(id) AS (SELECT ? UNION ALL SELECT u.parent_unit_id FROM church_units u JOIN ancestors a ON u.id=a.id WHERE u.parent_unit_id IS NOT NULL AND u.church_id=?) SELECT a.id FROM user_unit_access a JOIN ancestors x ON x.id=a.unit_id WHERE a.church_id=? AND a.user_id=? AND a.role IN (${roles.map(()=>'?').join(',')}) AND (a.unit_id=? OR a.include_children=1) LIMIT 1`).bind(unitId,session.churchId,session.churchId,session.id,...roles,unitId).first();return Boolean(row)}
export async function audit(request:Request,session:ChurchSession,action:string,entityType:string,entityId?:string,metadata?:Record<string,unknown>){await env.DB.prepare('INSERT INTO audit_logs (id,church_id,actor_user_id,action,entity_type,entity_id,metadata,ip_address,created_at) VALUES (?,?,?,?,?,?,?,?,?)').bind(crypto.randomUUID(),session.churchId,session.id,action,entityType,entityId||null,metadata?JSON.stringify(metadata):null,request.headers.get('cf-connecting-ip'),Date.now()).run()}
export async function hierarchyAccess(session:ChurchSession,targetChurchId:string,moduleCode:string){if(targetChurchId===session.churchId)return{allowed:true,level:'manage',personalData:true};const row=await env.DB.prepare(`SELECT a.access_level,a.include_personal_data FROM saas_organization_links l JOIN saas_hierarchy_module_access a ON a.link_id=l.id AND a.module_code=? WHERE l.parent_church_id=? AND l.child_church_id=? AND l.status='active' LIMIT 1`).bind(moduleCode,session.churchId,targetChurchId).first<{access_level:string;include_personal_data:number}>();return{allowed:Boolean(row&&row.access_level!=='none'),level:row?.access_level||'none',personalData:Boolean(row?.include_personal_data)}}
