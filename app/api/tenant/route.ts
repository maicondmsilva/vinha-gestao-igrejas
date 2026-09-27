import { env } from 'cloudflare:workers';
import { NextResponse } from 'next/server';
import { sessionFrom } from '../_auth';

const defaultModules=['members','units','events','kids','finance','cells','scales','worship','communication','broadcasts','reports'];

export async function GET(request:Request){
 const session=await sessionFrom(request);if(!session)return NextResponse.json({error:'Autenticação necessária.'},{status:401});const church=await env.DB.prepare('SELECT id,name,app_name,slug,primary_color,accent_color,logo_key,opening_video_key,senior_pastor_name,created_at FROM churches WHERE id=?').bind(session.churchId).first();
 let subscription=await env.DB.prepare(`SELECT s.*,p.code plan_code,p.name plan_name,p.description plan_description,p.base_price_cents FROM saas_subscriptions s JOIN saas_plans p ON p.id=s.plan_id WHERE s.church_id=?`).bind(session.churchId).first<Record<string,unknown>>();
 if(!subscription){const id=crypto.randomUUID(),now=Date.now(),trial=now+30*86400000;await env.DB.prepare(`INSERT INTO saas_subscriptions (id,church_id,plan_id,status,app_addon,trial_ends_at,created_at,updated_at) VALUES (?,?,'plan-complete','trialing',1,?,?,?)`).bind(id,session.churchId,trial,now,now).run();await env.DB.batch(defaultModules.map(code=>env.DB.prepare('INSERT INTO saas_subscription_modules (id,subscription_id,module_code,enabled,created_at) VALUES (?,?,?,1,?)').bind(crypto.randomUUID(),id,code,now)));subscription=await env.DB.prepare(`SELECT s.*,p.code plan_code,p.name plan_name,p.description plan_description,p.base_price_cents FROM saas_subscriptions s JOIN saas_plans p ON p.id=s.plan_id WHERE s.church_id=?`).bind(session.churchId).first<Record<string,unknown>>();}
 const modules=await env.DB.prepare(`SELECT m.module_code,m.enabled,m.limit_value FROM saas_subscription_modules m JOIN saas_subscriptions s ON s.id=m.subscription_id WHERE s.church_id=? ORDER BY m.module_code`).bind(session.churchId).all();
 const units=await env.DB.prepare(`SELECT COUNT(*) total FROM church_units WHERE church_id=? AND status='active'`).bind(session.churchId).first<{total:number}>();
 const people=await env.DB.prepare(`SELECT COUNT(*) total FROM people WHERE church_id=? AND status!='rejected'`).bind(session.churchId).first<{total:number}>();
 return NextResponse.json({church,subscription,modules:modules.results,usage:{units:units?.total||0,people:people?.total||0},session});
}
