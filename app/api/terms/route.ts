import { env } from 'cloudflare:workers';
import { NextResponse } from 'next/server';
import { audit, authorize } from '../_auth';

const CHURCH_ID = 'vinha-demo';
const defaults = [
  ['privacy','Tratamento de dados pessoais','Autorizo o tratamento dos meus dados pessoais para cadastro, cuidado pastoral, participação em atividades e comunicação institucional.'],
  ['image','Uso de imagem e voz','Autorizo o uso da minha imagem e voz em registros de cultos, eventos e comunicações institucionais da igreja.'],
  ['messages','Comunicações','Autorizo o envio de mensagens da igreja por aplicativo, e-mail, SMS ou mensageria.'],
  ['minors','Responsável por criança ou adolescente','Declaro ser responsável legal ou pessoa autorizada e consinto com o cadastro do menor e o tratamento dos dados necessários à sua segurança na Área Kids.'],
];

async function ensureDefaults() {
  const now = Date.now();
  await env.DB.prepare(`INSERT OR IGNORE INTO churches (id,name,app_name,slug,primary_color,accent_color,senior_pastor_name,created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)`).bind(CHURCH_ID,'Igreja Central','Central Conecta','igreja-central','#285c45','#d8b769','Pastor titular',now).run();
  for (const [type,title,content] of defaults) await env.DB.prepare(`INSERT OR IGNORE INTO consent_terms
    (id,church_id,consent_type,title,version,content,effective_at,active,created_at) VALUES (?, ?, ?, ?, '1.0', ?, ?, 1, ?)`)
    .bind(`${CHURCH_ID}-${type}-1`,CHURCH_ID,type,title,content,now,now).run();
}

export async function GET(request:Request) {
  const auth=await authorize(request,'terms.read'); if(auth.response)return auth.response;
  await ensureDefaults();
  const church = await env.DB.prepare('SELECT name, senior_pastor_name, senior_pastor_cpf FROM churches WHERE id=?').bind(CHURCH_ID).first();
  const terms = await env.DB.prepare('SELECT id, consent_type, title, version, content, effective_at FROM consent_terms WHERE church_id=? AND active=1 ORDER BY consent_type').bind(CHURCH_ID).all();
  return NextResponse.json({ church, terms: terms.results });
}

export async function PATCH(request: Request) {
  const auth=await authorize(request,'terms.write'); if(auth.response)return auth.response;
  await ensureDefaults(); const data = await request.json<{pastorName?:string;pastorCpf?:string;type?:string;title?:string;content?:string}>();
  if (data.pastorName) await env.DB.prepare('UPDATE churches SET senior_pastor_name=?, senior_pastor_cpf=? WHERE id=?').bind(data.pastorName,data.pastorCpf||null,CHURCH_ID).run();
  if (data.type && data.title && data.content) {
    const current = await env.DB.prepare('SELECT version FROM consent_terms WHERE church_id=? AND consent_type=? AND active=1').bind(CHURCH_ID,data.type).first<{version:string}>();
    const nextVersion = `${Number(current?.version||'1')+0.1}`.replace(/(\.\d)\d+$/,'$1'); const now=Date.now();
    await env.DB.batch([
      env.DB.prepare('UPDATE consent_terms SET active=0 WHERE church_id=? AND consent_type=?').bind(CHURCH_ID,data.type),
      env.DB.prepare(`INSERT INTO consent_terms (id,church_id,consent_type,title,version,content,effective_at,active,created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)`).bind(crypto.randomUUID(),CHURCH_ID,data.type,data.title,nextVersion,data.content,now,now),
    ]);
  }
  await audit(request,auth.session!,'terms.updated','consent_term',data.type,{pastorUpdated:Boolean(data.pastorName)});
  return NextResponse.json({ok:true});
}
