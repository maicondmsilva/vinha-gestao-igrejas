import { withLegacyContainment } from '../../../lib/release-availability';
import {env} from 'cloudflare:workers';
import {NextResponse} from 'next/server';
import {audit, sessionFrom} from '../../_auth';

async function legacyPOST(request:Request){
  const session=await sessionFrom(request);
  if(!session)return NextResponse.json({error:'Autenticação necessária.'},{status:401});
  if(!session.personId)return NextResponse.json({error:'Seu usuário precisa estar vinculado ao cadastro de responsável.'},{status:409});
  const data=await request.json<{type?:string;childId?:string;granted?:boolean}>();
  if(!data.type)return NextResponse.json({error:'Consentimento inválido.'},{status:400});
  if(data.type==='minors'){
    if(!data.childId)return NextResponse.json({error:'Criança obrigatória.'},{status:400});
    const link=await env.DB.prepare('SELECT id FROM child_guardians WHERE church_id=? AND child_id=? AND guardian_person_id=? AND can_manage=1').bind(session.churchId,data.childId,session.personId).first();
    if(!link)return NextResponse.json({error:'Você não está autorizado a conceder consentimento para esta criança.'},{status:403});
  }
  const term=await env.DB.prepare('SELECT id,title,version,content FROM consent_terms WHERE church_id=? AND consent_type=? AND active=1 ORDER BY effective_at DESC LIMIT 1').bind(session.churchId,data.type).first<Record<string,string>>();
  if(!term)return NextResponse.json({error:'Termo não encontrado.'},{status:404});
  const guardian=await env.DB.prepare('SELECT id,full_name,cpf,email,phone FROM people WHERE church_id=? AND id=?').bind(session.churchId,session.personId).first();
  if(!guardian)return NextResponse.json({error:'Responsável não encontrado.'},{status:404});
  const child=data.childId?await env.DB.prepare('SELECT id,full_name,birth_date FROM children WHERE church_id=? AND id=?').bind(session.churchId,data.childId).first():null;
  const id=crypto.randomUUID(),now=Date.now();
  const snapshot={term,guardian,child,acceptedAt:new Date(now).toISOString()};
  await env.DB.prepare(`INSERT INTO person_consents (id,church_id,person_id,consent_type,granted,source,term_id,accepted_by_person_id,subject_person_id,acceptance_snapshot,ip_address,user_agent,granted_at) VALUES (?, ?, ?, ?, ?, 'app', ?, ?, ?, ?, ?, ?, ?)`).bind(id,session.churchId,session.personId,data.type,data.granted===false?0:1,term.id,session.personId,data.childId||session.personId,JSON.stringify(snapshot),request.headers.get('cf-connecting-ip'),request.headers.get('user-agent'),now).run();
  await audit(request,session,'consent.accept','person_consent',id,{consentType:data.type,childId:data.childId||null,termVersion:term.version});
  return NextResponse.json({id,acceptedAt:now,termVersion:term.version});
}

async function legacyPATCH(request:Request){
  const session=await sessionFrom(request);
  if(!session)return NextResponse.json({error:'Autenticação necessária.'},{status:401});
  if(!session.personId)return NextResponse.json({error:'Seu usuário precisa estar vinculado ao cadastro de responsável.'},{status:409});
  const data=await request.json<{consentId?:string}>();
  if(!data.consentId)return NextResponse.json({error:'Dados inválidos.'},{status:400});
  const now=Date.now();
  const result=await env.DB.prepare('UPDATE person_consents SET granted=0,revoked_at=? WHERE id=? AND church_id=? AND accepted_by_person_id=? AND revoked_at IS NULL').bind(now,data.consentId,session.churchId,session.personId).run();
  if(!result.meta.changes)return NextResponse.json({error:'Aceite não encontrado ou sem permissão.'},{status:404});
  await audit(request,session,'consent.revoke','person_consent',data.consentId,{});
  return NextResponse.json({ok:true});
}

export const POST = withLegacyContainment(legacyPOST);
export const PATCH = withLegacyContainment(legacyPATCH);
