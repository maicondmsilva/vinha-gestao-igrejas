import {env} from 'cloudflare:workers';
import {NextResponse} from 'next/server';
import {audit,authorize,unitGrant} from '../../_auth';

const bool=(value:unknown)=>value===true||value===1;

export async function GET(request:Request){
 const auth=await authorize(request,'users.read');if(auth.response)return auth.response;const session=auth.session!;
 const [policy,users,events,units,recovery]=await Promise.all([
  env.DB.prepare('SELECT * FROM auth_security_policies WHERE church_id=?').bind(session.churchId).first(),
  env.DB.prepare(`SELECT u.id,u.name,u.email,u.role,u.status,u.person_id,p.full_name person_name,s.default_unit_id,s.identity_provider,s.email_verified_at,s.phone_verified_at,s.mfa_status,s.last_seen_at,s.locked_until,cu.name default_unit_name FROM church_users u LEFT JOIN user_security_profiles s ON s.user_id=u.id AND s.church_id=u.church_id LEFT JOIN people p ON p.id=u.person_id AND p.church_id=u.church_id LEFT JOIN church_units cu ON cu.id=s.default_unit_id WHERE u.church_id=? ORDER BY CASE u.role WHEN 'admin' THEN 0 WHEN 'pastor' THEN 1 ELSE 2 END,u.name`).bind(session.churchId).all(),
  env.DB.prepare(`SELECT e.event_type,e.identity_provider,e.ip_address,e.created_at,e.metadata,u.name user_name FROM user_login_events e JOIN church_users u ON u.id=e.user_id WHERE e.church_id=? ORDER BY e.created_at DESC LIMIT 30`).bind(session.churchId).all(),
  env.DB.prepare("SELECT id,name,type FROM church_units WHERE church_id=? AND status='active' ORDER BY CASE type WHEN 'headquarters' THEN 0 ELSE 1 END,name").bind(session.churchId).all(),
  env.DB.prepare("SELECT id,email,request_type,status,public_protocol,requested_at FROM access_recovery_requests WHERE church_id=? AND status IN ('pending','in_review') ORDER BY requested_at DESC LIMIT 30").bind(session.churchId).all()
 ]);
 return NextResponse.json({policy:policy||{require_mfa_admins:1,require_mfa_finance:1,require_verified_email:1,require_verified_phone_members:0,session_timeout_minutes:480,max_failed_attempts:5},users:users.results,events:events.results,units:units.results,recovery:recovery.results,currentUserId:session.id,provider:'openai_sites'});
}

export async function PATCH(request:Request){
 const auth=await authorize(request,'*');if(auth.response)return auth.response;const session=auth.session!,d=await request.json<Record<string,unknown>>(),now=Date.now();
 if(d.action==='policy'){
  const timeout=Math.min(1440,Math.max(30,Number(d.sessionTimeoutMinutes)||480)),attempts=Math.min(10,Math.max(3,Number(d.maxFailedAttempts)||5));
  await env.DB.prepare(`INSERT INTO auth_security_policies (church_id,require_mfa_admins,require_mfa_finance,require_verified_email,require_verified_phone_members,session_timeout_minutes,max_failed_attempts,updated_by_user_id,updated_at) VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(church_id) DO UPDATE SET require_mfa_admins=excluded.require_mfa_admins,require_mfa_finance=excluded.require_mfa_finance,require_verified_email=excluded.require_verified_email,require_verified_phone_members=excluded.require_verified_phone_members,session_timeout_minutes=excluded.session_timeout_minutes,max_failed_attempts=excluded.max_failed_attempts,updated_by_user_id=excluded.updated_by_user_id,updated_at=excluded.updated_at`).bind(session.churchId,bool(d.requireMfaAdmins)?1:0,bool(d.requireMfaFinance)?1:0,bool(d.requireVerifiedEmail)?1:0,bool(d.requireVerifiedPhoneMembers)?1:0,timeout,attempts,session.id,now).run();
  await audit(request,session,'security.policy_updated','auth_security_policy',session.churchId,{timeout,attempts});return NextResponse.json({ok:true,message:'Políticas de acesso atualizadas.'});
 }
 if(d.action==='default_unit'){
  const userId=String(d.userId||''),unitId=String(d.unitId||'');if(!userId||!unitId)return NextResponse.json({error:'Selecione o usuário e a unidade.'},{status:400});
  const target=await env.DB.prepare('SELECT id,role FROM church_users WHERE id=? AND church_id=?').bind(userId,session.churchId).first<{id:string;role:string}>(),unit=await env.DB.prepare("SELECT id FROM church_units WHERE id=? AND church_id=? AND status='active'").bind(unitId,session.churchId).first();if(!target||!unit)return NextResponse.json({error:'Usuário ou unidade inválida.'},{status:404});
  if(!['admin','pastor'].includes(target.role)&&!(await unitGrant({...session,id:userId,role:target.role},unitId,['unit_admin','pastor','secretary','events_manager','communication','finance','viewer'])))return NextResponse.json({error:'A unidade precisa estar entre os acessos permitidos desse usuário.'},{status:409});
  await env.DB.prepare(`INSERT INTO user_security_profiles (user_id,church_id,default_unit_id,identity_provider,created_at,updated_at) VALUES (?,?,?,'openai_sites',?,?) ON CONFLICT(user_id) DO UPDATE SET default_unit_id=excluded.default_unit_id,updated_at=excluded.updated_at`).bind(userId,session.churchId,unitId,now,now).run();
  await env.DB.prepare("INSERT INTO user_login_events (id,church_id,user_id,event_type,identity_provider,ip_address,user_agent,metadata,created_at) VALUES (?,?,?,'unit_changed','openai_sites',?,?,?,?)").bind(crypto.randomUUID(),session.churchId,userId,request.headers.get('cf-connecting-ip'),request.headers.get('user-agent'),JSON.stringify({unitId,changedBy:session.id}),now).run();await audit(request,session,'security.default_unit_updated','church_user',userId,{unitId});return NextResponse.json({ok:true,message:'Unidade principal atualizada.'});
 }
 if(d.action==='recovery'){
  const id=String(d.id||''),status=String(d.status||'');if(!id||!['in_review','resolved','cancelled'].includes(status))return NextResponse.json({error:'Atualização de recuperação inválida.'},{status:400});const result=await env.DB.prepare('UPDATE access_recovery_requests SET status=?,reviewed_by_user_id=?,review_note=?,reviewed_at=? WHERE id=? AND church_id=?').bind(status,session.id,String(d.note||''),now,id,session.churchId).run();if(!result.meta.changes)return NextResponse.json({error:'Solicitação não encontrada.'},{status:404});await audit(request,session,`security.recovery_${status}`,'access_recovery',id);return NextResponse.json({ok:true,message:status==='resolved'?'Recuperação concluída.':'Solicitação atualizada.'});
 }
 return NextResponse.json({error:'Ação inválida.'},{status:400});
}
