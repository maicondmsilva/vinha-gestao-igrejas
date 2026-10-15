import { withLegacyContainment } from '../../../lib/release-availability';
import {env} from 'cloudflare:workers';
import {NextResponse} from 'next/server';

const clean=(v:unknown)=>String(v||'').trim().toLowerCase();
async function hash(value:string){const data=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value));return [...new Uint8Array(data)].map(x=>x.toString(16).padStart(2,'0')).join('')}

async function legacyPOST(request:Request){
 const d=await request.json<Record<string,unknown>>(),email=clean(d.email),slug=clean(d.churchSlug).replace(/[^a-z0-9-]/g,''),type=['access','email_changed','mfa','locked'].includes(String(d.requestType))?String(d.requestType):'access';if(!/^\S+@\S+\.\S+$/.test(email))return NextResponse.json({error:'Informe um e-mail válido.'},{status:400});
 const ip=request.headers.get('cf-connecting-ip')||'unknown',ipHash=await hash(ip),recent=await env.DB.prepare('SELECT COUNT(*) total FROM access_recovery_requests WHERE ip_hash=? AND requested_at>?').bind(ipHash,Date.now()-3600000).first<{total:number}>();if(Number(recent?.total)>=3)return NextResponse.json({error:'Aguarde antes de enviar outra solicitação.'},{status:429});
 const church=slug?await env.DB.prepare('SELECT id FROM churches WHERE slug=?').bind(slug).first<{id:string}>():await env.DB.prepare('SELECT church_id id FROM church_users WHERE lower(email)=? LIMIT 1').bind(email).first<{id:string}>(),protocol=`VR-${crypto.randomUUID().replace(/-/g,'').slice(0,10).toUpperCase()}`,now=Date.now();
 await env.DB.prepare("INSERT INTO access_recovery_requests (id,church_id,email,church_slug,request_type,status,public_protocol,ip_hash,user_agent,requested_at) VALUES (?,?,?,?,?,'pending',?,?,?,?)").bind(crypto.randomUUID(),church?.id||null,email,slug||null,type,protocol,ipHash,request.headers.get('user-agent'),now).run();return NextResponse.json({ok:true,protocol,message:'Se os dados corresponderem a uma conta, a administração receberá a solicitação.'},{status:202});
}

export const POST = withLegacyContainment(legacyPOST);
