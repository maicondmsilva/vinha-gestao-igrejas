import {env} from 'cloudflare:workers';
import {NextResponse} from 'next/server';
import {platformAudit,platformSessionFrom} from '../../_auth';

type Rule={code:string;name:string;description:string;enabled:number;threshold_days:number;priority:string};
const day=86400000;

export async function GET(request:Request){
 if(!await platformSessionFrom(request))return NextResponse.json({error:'Acesso exclusivo da administração Vinha.'},{status:403});
 const [rules,tasks]=await Promise.all([
  env.DB.prepare('SELECT * FROM saas_lifecycle_rules ORDER BY code').all(),
  env.DB.prepare(`SELECT t.*,c.name church_name,c.primary_color FROM saas_customer_tasks t JOIN churches c ON c.id=t.church_id ORDER BY CASE t.status WHEN 'open' THEN 0 WHEN 'in_progress' THEN 1 ELSE 2 END,CASE t.priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END,COALESCE(t.due_at,t.created_at)`).all()
 ]);
 return NextResponse.json({rules:rules.results,tasks:tasks.results});
}

export async function POST(request:Request){
 const session=await platformSessionFrom(request);if(!session)return NextResponse.json({error:'Acesso exclusivo da administração Vinha.'},{status:403});
 const data=await request.json<Record<string,unknown>>(),now=Date.now();
 if(data.action==='manual'){
  const churchId=String(data.churchId||''),title=String(data.title||'').trim();
  if(!churchId||!title)return NextResponse.json({error:'Selecione o cliente e informe a tarefa.'},{status:400});
  const id=crypto.randomUUID();
  await env.DB.prepare("INSERT INTO saas_customer_tasks (id,church_id,rule_code,title,description,priority,status,due_at,assigned_to,created_at,updated_at) VALUES (?,?, 'manual',?,?,?,?,?,?,?,?)").bind(id,churchId,title,String(data.description||'').trim()||null,['low','medium','high','critical'].includes(String(data.priority))?String(data.priority):'medium','open',data.dueAt?Number(data.dueAt):null,String(data.assignedTo||'').trim()||null,now,now).run();
  await platformAudit(request,session,'lifecycle.task_created','customer_task',id,{churchId});return NextResponse.json({ok:true,id});
 }
 if(data.action!=='scan')return NextResponse.json({error:'Ação inválida.'},{status:400});
 const rules=(await env.DB.prepare('SELECT * FROM saas_lifecycle_rules WHERE enabled=1').all<Rule>()).results,statements:ReturnType<typeof env.DB.prepare>[]=[],counts:Record<string,number>={};
 for(const rule of rules){
  if(rule.code==='trial_ending'){
   const rows=(await env.DB.prepare("SELECT c.id,c.name,s.trial_ends_at FROM churches c JOIN saas_subscriptions s ON s.church_id=c.id WHERE s.status='trialing' AND s.trial_ends_at IS NOT NULL AND s.trial_ends_at<=?").bind(now+rule.threshold_days*day).all<Record<string,unknown>>()).results;
   counts[rule.code]=rows.length;for(const row of rows)statements.push(env.DB.prepare("INSERT OR IGNORE INTO saas_customer_tasks (id,church_id,rule_code,title,description,priority,status,due_at,source_key,created_at,updated_at) VALUES (?,?,?,?,?,?,'open',?,?,?,?)").bind(crypto.randomUUID(),row.id,rule.code,'Converter cliente antes do fim do teste',`O período de avaliação de ${row.name} está próximo do fim.`,rule.priority,Number(row.trial_ends_at),`${rule.code}:${row.id}:${row.trial_ends_at}`,now,now));
  }
  if(rule.code==='onboarding_stalled'){
   const rows=(await env.DB.prepare("SELECT c.id,c.name,o.current_step,o.updated_at FROM churches c JOIN saas_onboarding_progress o ON o.church_id=c.id WHERE o.status='in_progress' AND o.updated_at<=?").bind(now-rule.threshold_days*day).all<Record<string,unknown>>()).results;
   counts[rule.code]=rows.length;for(const row of rows)statements.push(env.DB.prepare("INSERT OR IGNORE INTO saas_customer_tasks (id,church_id,rule_code,title,description,priority,status,due_at,source_key,created_at,updated_at) VALUES (?,?,?,?,?,?,'open',?,?,?,?)").bind(crypto.randomUUID(),row.id,rule.code,'Retomar onboarding do cliente',`${row.name} está sem avançar desde a etapa ${row.current_step}.`,rule.priority,now,`${rule.code}:${row.id}:${row.current_step}:${row.updated_at}`,now,now));
  }
  if(rule.code==='payment_overdue'){
   const rows=(await env.DB.prepare("SELECT i.id invoice_id,i.church_id,i.reference_month,i.due_at,c.name FROM saas_invoices i JOIN churches c ON c.id=i.church_id WHERE i.status='open' AND i.due_at<?").bind(now-rule.threshold_days*day).all<Record<string,unknown>>()).results;
   counts[rule.code]=rows.length;for(const row of rows)statements.push(env.DB.prepare("INSERT OR IGNORE INTO saas_customer_tasks (id,church_id,rule_code,title,description,priority,status,due_at,source_key,created_at,updated_at) VALUES (?,?,?,?,?,?,'open',?,?,?,?)").bind(crypto.randomUUID(),row.church_id,rule.code,'Regularizar pagamento vencido',`A cobrança ${row.reference_month} de ${row.name} está vencida.`,rule.priority,Number(row.due_at),`${rule.code}:${row.invoice_id}`,now,now));
  }
 }
 if(statements.length)await env.DB.batch(statements);
 await platformAudit(request,session,'lifecycle.scan_completed','lifecycle',undefined,{candidates:counts});
 return NextResponse.json({ok:true,candidates:counts});
}

export async function PATCH(request:Request){
 const session=await platformSessionFrom(request);if(!session)return NextResponse.json({error:'Acesso exclusivo da administração Vinha.'},{status:403});
 const data=await request.json<Record<string,unknown>>(),id=String(data.id||''),status=String(data.status||'');
 if(!id||!['open','in_progress','done','dismissed'].includes(status))return NextResponse.json({error:'Atualização inválida.'},{status:400});
 const now=Date.now(),result=await env.DB.prepare('UPDATE saas_customer_tasks SET status=?,assigned_to=COALESCE(?,assigned_to),completed_at=?,updated_at=? WHERE id=?').bind(status,String(data.assignedTo||'').trim()||null,['done','dismissed'].includes(status)?now:null,now,id).run();
 if(!result.meta.changes)return NextResponse.json({error:'Tarefa não encontrada.'},{status:404});
 await platformAudit(request,session,'lifecycle.task_updated','customer_task',id,{status});return NextResponse.json({ok:true});
}

export async function PUT(request:Request){
 const session=await platformSessionFrom(request);if(!session)return NextResponse.json({error:'Acesso exclusivo da administração Vinha.'},{status:403});
 const data=await request.json<{rules?:Array<{code:string;enabled:boolean;thresholdDays:number;priority:string}>}>(),now=Date.now();
 const statements=(data.rules||[]).filter(r=>['trial_ending','onboarding_stalled','payment_overdue'].includes(r.code)).map(r=>env.DB.prepare('UPDATE saas_lifecycle_rules SET enabled=?,threshold_days=?,priority=?,updated_at=? WHERE code=?').bind(r.enabled?1:0,Math.max(0,Math.min(90,Number(r.thresholdDays)||0)),['low','medium','high','critical'].includes(r.priority)?r.priority:'medium',now,r.code));
 if(statements.length)await env.DB.batch(statements);await platformAudit(request,session,'lifecycle.rules_updated','lifecycle');return NextResponse.json({ok:true});
}
