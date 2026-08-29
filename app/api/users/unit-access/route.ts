import { env } from 'cloudflare:workers';
import { NextResponse } from 'next/server';
import { audit, authorize, CHURCH_ID } from '../../_auth';

const accessRoles=['unit_admin','pastor','secretary','events_manager','communication','finance','viewer'];
type Entry={unitId?:string;role?:string;includeChildren?:boolean};

export async function PATCH(request:Request){
 const auth=await authorize(request,'*');if(auth.response)return auth.response;
 const data=await request.json<{userId?:string;entries?:Entry[]}>();if(!data.userId||!Array.isArray(data.entries))return NextResponse.json({error:'Acessos inválidos.'},{status:400});
 const target=await env.DB.prepare('SELECT id,role FROM church_users WHERE id=? AND church_id=?').bind(data.userId,CHURCH_ID).first<{id:string;role:string}>();if(!target)return NextResponse.json({error:'Usuário não encontrado.'},{status:404});
 const unique=new Map<string,Entry>();for(const entry of data.entries){if(entry.unitId&&entry.role&&accessRoles.includes(entry.role))unique.set(entry.unitId,entry)}
 if(unique.size){const placeholders=[...unique.keys()].map(()=>'?').join(',');const existing=await env.DB.prepare(`SELECT id FROM church_units WHERE church_id=? AND id IN (${placeholders})`).bind(CHURCH_ID,...unique.keys()).all<{id:string}>();if(existing.results.length!==unique.size)return NextResponse.json({error:'Uma das unidades não pertence a esta igreja.'},{status:400})}
 const statements=[env.DB.prepare('DELETE FROM user_unit_access WHERE church_id=? AND user_id=?').bind(CHURCH_ID,data.userId)];const now=Date.now();for(const entry of unique.values())statements.push(env.DB.prepare('INSERT INTO user_unit_access (id,church_id,user_id,unit_id,role,include_children,created_at) VALUES (?,?,?,?,?,?,?)').bind(crypto.randomUUID(),CHURCH_ID,data.userId,entry.unitId,entry.role,entry.includeChildren?1:0,now));await env.DB.batch(statements);
 await audit(request,auth.session!,'user.unit_access_updated','church_user',data.userId,{units:[...unique.values()]});return NextResponse.json({ok:true,count:unique.size});
}
