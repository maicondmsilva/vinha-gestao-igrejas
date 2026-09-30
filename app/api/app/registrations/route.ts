import { env } from 'cloudflare:workers';
import { NextResponse } from 'next/server';
import { audit, authorize } from '../../_auth';

const clean=(v:unknown)=>String(v||'').trim();
const digits=(v:unknown)=>clean(v).replace(/\D/g,'');

export async function GET(request:Request){
 const auth=await authorize(request,'people.read');if(auth.response)return auth.response;
 const churchId=auth.session!.churchId;
 const rows=await env.DB.prepare(`SELECT r.*,u.name unit_name,u.type unit_type,p.full_name person_name
   FROM app_registration_requests r JOIN church_units u ON u.id=r.unit_id AND u.church_id=r.church_id
   LEFT JOIN people p ON p.id=r.matched_person_id AND p.church_id=r.church_id
   WHERE r.church_id=? ORDER BY CASE r.status WHEN 'matched_pending' THEN 0 WHEN 'new_pending' THEN 1 ELSE 2 END,r.requested_at DESC`).bind(churchId).all();
 return NextResponse.json({requests:rows.results});
}

export async function POST(request:Request){
 const externalUserId=request.headers.get('oai-authenticated-user-id'),authenticatedEmail=clean(request.headers.get('oai-authenticated-user-email')).toLowerCase();
 if(!externalUserId||!authenticatedEmail)return NextResponse.json({error:'Entre com sua conta antes de solicitar o cadastro.'},{status:401});
 const d=await request.json<Record<string,unknown>>(),fullName=clean(d.fullName),email=clean(d.email).toLowerCase(),phone=digits(d.phone),cpf=digits(d.cpf),birthDate=clean(d.birthDate),unitId=clean(d.unitId);
 if(!fullName||!email||!phone||!unitId)return NextResponse.json({error:'Nome, e-mail, celular e unidade são obrigatórios.'},{status:400});
 if(email!==authenticatedEmail)return NextResponse.json({error:'Use o mesmo e-mail da conta com a qual você entrou.'},{status:403});
 const unit=await env.DB.prepare(`SELECT id,church_id FROM church_units WHERE id=? AND status='active'`).bind(unitId).first<{id:string;church_id:string}>();
 if(!unit)return NextResponse.json({error:'A unidade selecionada não está disponível.'},{status:400});
 const churchId=unit.church_id,match=await env.DB.prepare(`SELECT id,full_name,cpf,email,phone,birth_date FROM people WHERE church_id=? AND ((? != '' AND REPLACE(REPLACE(REPLACE(cpf,'.',''),'-',''),'/','')=?) OR lower(email)=? OR REPLACE(REPLACE(REPLACE(REPLACE(phone,'(',''),')',''),'-',''),' ','')=?) LIMIT 1`).bind(churchId,cpf,cpf,email,phone).first<Record<string,string>>();
 let score=0,reason='';if(match){const reasons=[];if(cpf&&digits(match.cpf)===cpf){score+=65;reasons.push('CPF')}if(email&&match.email?.toLowerCase()===email){score+=20;reasons.push('e-mail')}if(phone&&digits(match.phone)===phone){score+=10;reasons.push('celular')}if(birthDate&&match.birth_date===birthDate){score+=5;reasons.push('nascimento')}reason=reasons.join(', ')}
 const duplicate=await env.DB.prepare("SELECT id FROM app_registration_requests WHERE church_id=? AND external_user_id=? AND status IN ('matched_pending','new_pending') LIMIT 1").bind(churchId,externalUserId).first();
 if(duplicate)return NextResponse.json({error:'Você já possui uma solicitação aguardando análise nesta igreja.'},{status:409});
 const now=Date.now(),id=crypto.randomUUID(),personId=match?.id||crypto.randomUUID(),status=match?'matched_pending':'new_pending';
 const statements=[];
 if(!match)statements.push(env.DB.prepare(`INSERT INTO people (id,church_id,full_name,birth_date,cpf,email,phone,journey_status,campus,group_name,joined_at,baptized,tags,app_role,status,created_at) VALUES (?,?,?,?,?,?,?,?,?,'Sem grupo',?,0,'[]','member','pending_approval',?)`).bind(personId,churchId,fullName,birthDate||null,cpf||null,email,phone,'Em integração',unitId,now,now));
 statements.push(env.DB.prepare(`INSERT INTO app_registration_requests (id,church_id,unit_id,external_user_id,matched_person_id,full_name,cpf,email,phone,birth_date,theme_preference,status,match_score,match_reason,requested_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).bind(id,churchId,unitId,externalUserId,personId,fullName,cpf||null,email,phone,birthDate||null,clean(d.themePreference)||'system',status,score,reason||null,now));
 await env.DB.batch(statements);return NextResponse.json({id,matched:Boolean(match),status},{status:201});
}

export async function PATCH(request:Request){
 const auth=await authorize(request,'people.write');if(auth.response)return auth.response;const d=await request.json<Record<string,string>>();
 const churchId=auth.session!.churchId;
 if(!d.id||!['approve','reject','merge'].includes(d.action))return NextResponse.json({error:'Ação inválida.'},{status:400});
 const item=await env.DB.prepare(`SELECT * FROM app_registration_requests WHERE id=? AND church_id=?`).bind(d.id,churchId).first<Record<string,string>>();if(!item)return NextResponse.json({error:'Solicitação não encontrada.'},{status:404});
 const now=Date.now(),approved=d.action!=='reject',next=approved?'approved':'rejected';
 const statements=[env.DB.prepare(`UPDATE app_registration_requests SET status=?,reviewed_by_user_id=?,reviewed_at=?,decision_note=? WHERE id=? AND church_id=?`).bind(next,auth.session!.id,now,d.action==='merge'?'Cadastro conferido e vinculado.':approved?'Novo cadastro aprovado.':'Solicitação recusada.',d.id,churchId)];
 if(approved){const existingUser=await env.DB.prepare('SELECT id FROM church_users WHERE church_id=? AND external_user_id=?').bind(churchId,item.external_user_id).first<{id:string}>(),userId=existingUser?.id||crypto.randomUUID();statements.push(env.DB.prepare(`UPDATE people SET status='active',campus=? WHERE id=? AND church_id=?`).bind(item.unit_id,item.matched_person_id,churchId));statements.push(env.DB.prepare(`INSERT OR IGNORE INTO church_users (id,church_id,person_id,external_user_id,email,name,role,status,created_at) VALUES (?,?,?,?,?,?,'member','active',?)`).bind(userId,churchId,item.matched_person_id,item.external_user_id,item.email,item.full_name,now));statements.push(env.DB.prepare(`UPDATE church_users SET person_id=?,status='active' WHERE church_id=? AND external_user_id=?`).bind(item.matched_person_id,churchId,item.external_user_id));statements.push(env.DB.prepare("INSERT OR IGNORE INTO user_security_profiles (user_id,church_id,default_unit_id,identity_provider,email_verified_at,mfa_status,created_at,updated_at) VALUES (?,?,?,'openai_sites',?,'not_enrolled',?,?)").bind(userId,churchId,item.unit_id,now,now,now));}
 else if(item.status==='new_pending')statements.push(env.DB.prepare(`UPDATE people SET status='rejected' WHERE id=? AND church_id=? AND status='pending_approval'`).bind(item.matched_person_id,churchId));
 await env.DB.batch(statements);await audit(request,auth.session!,`app.registration.${next}`,'app_registration',d.id,{personId:item.matched_person_id,unitId:item.unit_id});return NextResponse.json({ok:true,message:approved?'Cadastro aprovado e perfil integrado ao aplicativo.':'Solicitação recusada e registrada na auditoria.'});
}
