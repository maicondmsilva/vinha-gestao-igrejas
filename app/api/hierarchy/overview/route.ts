import {env} from 'cloudflare:workers';
import {NextResponse} from 'next/server';
import {audit,hierarchyAccess,sessionFrom} from '../../_auth';

type Grant={allowed:boolean;level:string;personalData:boolean};
const moduleNames:Record<string,string>={dashboard:'Visão geral',people:'Membresia',finance:'Financeiro',kids:'Kids',events:'Eventos',cells:'Células',scales:'Escalas',reports:'Relatórios'};

export async function GET(request:Request){
  const session=await sessionFrom(request);
  if(!session)return NextResponse.json({error:'Autenticação necessária.'},{status:401});
  const childId=new URL(request.url).searchParams.get('child')||'';
  if(!childId)return NextResponse.json({error:'Selecione uma igreja vinculada.'},{status:400});
  const link=await env.DB.prepare(`SELECT l.id,c.name,c.slug,c.app_name,c.primary_color,c.accent_color FROM saas_organization_links l JOIN churches c ON c.id=l.child_church_id WHERE l.parent_church_id=? AND l.child_church_id=? AND l.status='active' LIMIT 1`).bind(session.churchId,childId).first<Record<string,any>>();
  if(!link)return NextResponse.json({error:'Esta igreja não está vinculada à sua sede.'},{status:404});
  const codes=Object.keys(moduleNames),entries=await Promise.all(codes.map(async code=>[code,await hierarchyAccess(session,childId,code)] as [string,Grant])),grants=Object.fromEntries(entries) as Record<string,Grant>;
  const result:any={church:{id:childId,name:link.name,slug:link.slug,appName:link.app_name,primaryColor:link.primary_color,accentColor:link.accent_color},permissions:codes.map(code=>({code,name:moduleNames[code],...grants[code]})),generatedAt:Date.now()};
  if(grants.dashboard.allowed){
    const [people,events,children,revenue]=await Promise.all([
      env.DB.prepare('SELECT COUNT(*) total FROM people WHERE church_id=?').bind(childId).first<{total:number}>(),
      env.DB.prepare('SELECT COUNT(*) total FROM events WHERE church_id=?').bind(childId).first<{total:number}>(),
      env.DB.prepare("SELECT COUNT(*) total FROM children WHERE church_id=? AND status='active'").bind(childId).first<{total:number}>(),
      env.DB.prepare("SELECT COALESCE(SUM(amount_cents),0) total FROM event_payment_orders WHERE church_id=? AND status IN ('paid','approved','confirmed')").bind(childId).first<{total:number}>()
    ]);
    result.dashboard={people:Number(people?.total||0),events:Number(events?.total||0),children:Number(children?.total||0),revenueCents:Number(revenue?.total||0)};
  }
  if(grants.people.allowed){
    const summary=await env.DB.prepare(`SELECT COUNT(*) total,SUM(CASE WHEN journey_status='member' THEN 1 ELSE 0 END) members,SUM(CASE WHEN journey_status='visitor' THEN 1 ELSE 0 END) visitors FROM people WHERE church_id=?`).bind(childId).first<Record<string,number>>();
    result.people={summary};
    if(grants.people.level==='read'){
      const rows=await env.DB.prepare('SELECT id,full_name,email,phone,journey_status,group_name,joined_at FROM people WHERE church_id=? ORDER BY full_name LIMIT 60').bind(childId).all<Record<string,any>>();
      result.people.items=rows.results.map(p=>({...p,email:grants.people.personalData?p.email:null,phone:grants.people.personalData?p.phone:null}));
    }
  }
  if(grants.events.allowed){
    const summary=await env.DB.prepare(`SELECT COUNT(*) total,SUM(CASE WHEN starts_at>=? THEN 1 ELSE 0 END) upcoming,SUM(CASE WHEN status='published' THEN 1 ELSE 0 END) published FROM events WHERE church_id=?`).bind(Date.now(),childId).first<Record<string,number>>();
    result.events={summary};
    if(grants.events.level==='read'){const rows=await env.DB.prepare('SELECT id,title,category,format,starts_at,ends_at,status,capacity FROM events WHERE church_id=? ORDER BY starts_at DESC LIMIT 30').bind(childId).all();result.events.items=rows.results}
  }
  if(grants.finance.allowed){
    const summary=await env.DB.prepare(`SELECT COALESCE(SUM(amount_cents),0) total,SUM(CASE WHEN status IN ('paid','approved','confirmed') THEN amount_cents ELSE 0 END) received,SUM(CASE WHEN status IN ('created','pending') THEN amount_cents ELSE 0 END) pending,COUNT(*) transactions FROM event_payment_orders WHERE church_id=?`).bind(childId).first<Record<string,number>>();
    result.finance={summary};
    if(grants.finance.level==='read'){const rows=await env.DB.prepare(`SELECT o.id,o.provider,o.payment_method,o.amount_cents,o.status,o.created_at,r.full_name,r.email FROM event_payment_orders o JOIN event_registrations r ON r.id=o.registration_id WHERE o.church_id=? ORDER BY o.created_at DESC LIMIT 40`).bind(childId).all<Record<string,any>>();result.finance.items=rows.results.map(x=>({...x,full_name:grants.finance.personalData?x.full_name:'Participante protegido',email:grants.finance.personalData?x.email:null}))}
  }
  if(grants.kids.allowed){
    const summary=await env.DB.prepare(`SELECT COUNT(*) total,SUM(CASE WHEN status='active' THEN 1 ELSE 0 END) active FROM children WHERE church_id=?`).bind(childId).first<Record<string,number>>();
    const rooms=await env.DB.prepare(`SELECT r.id,r.name,r.capacity,r.location,COUNT(CASE WHEN c.status='checked_in' THEN 1 END) occupancy FROM kids_rooms r LEFT JOIN kids_sessions s ON s.room_id=r.id AND s.status='open' LEFT JOIN kids_checkins c ON c.session_id=s.id WHERE r.church_id=? AND r.status='active' GROUP BY r.id ORDER BY r.name`).bind(childId).all();
    result.kids={summary,rooms:rooms.results};
    if(grants.kids.level==='read'&&grants.kids.personalData){const children=await env.DB.prepare('SELECT id,full_name,birth_date,allergies,special_needs,status FROM children WHERE church_id=? ORDER BY full_name LIMIT 60').bind(childId).all();result.kids.children=children.results}
  }
  if(grants.cells.allowed){
    const summary=await env.DB.prepare(`SELECT COUNT(*) total,SUM(CASE WHEN status='active' THEN 1 ELSE 0 END) active,(SELECT COUNT(*) FROM cell_members cm WHERE cm.church_id=? AND cm.status='active') members,(SELECT COUNT(*) FROM cell_meetings mt WHERE mt.church_id=?) meetings FROM cells WHERE church_id=?`).bind(childId,childId,childId).first<Record<string,number>>();
    result.cells={summary};
    if(grants.cells.level==='read'){const rows=await env.DB.prepare(`SELECT c.id,c.name,c.meeting_day,c.meeting_time,c.status,COUNT(cm.id) members,l.full_name leader_name FROM cells c LEFT JOIN cell_members cm ON cm.cell_id=c.id AND cm.status='active' LEFT JOIN people l ON l.id=c.leader_person_id WHERE c.church_id=? GROUP BY c.id ORDER BY c.name`).bind(childId).all<Record<string,any>>();result.cells.items=rows.results.map(x=>({...x,leader_name:grants.cells.personalData?x.leader_name:'Liderança protegida'}))}
  }
  if(grants.scales.allowed){
    const summary=await env.DB.prepare(`SELECT COUNT(*) total,SUM(CASE WHEN status='published' THEN 1 ELSE 0 END) published,(SELECT COUNT(*) FROM schedule_positions p WHERE p.church_id=?) positions,(SELECT COUNT(*) FROM schedule_positions p WHERE p.church_id=? AND p.response_status='confirmed') confirmed,(SELECT COUNT(*) FROM schedule_positions p WHERE p.church_id=? AND p.response_status='conflict') conflicts FROM schedules WHERE church_id=?`).bind(childId,childId,childId,childId).first<Record<string,number>>();
    result.scales={summary};
    if(grants.scales.level==='read'){const rows=await env.DB.prepare(`SELECT s.id,s.title,s.starts_at,s.status,COUNT(p.id) positions,SUM(CASE WHEN p.response_status='confirmed' THEN 1 ELSE 0 END) confirmed FROM schedules s LEFT JOIN schedule_positions p ON p.schedule_id=s.id WHERE s.church_id=? GROUP BY s.id ORDER BY s.starts_at DESC LIMIT 20`).bind(childId).all();result.scales.items=rows.results}
  }
  result.placeholders=['reports'].filter(code=>grants[code].allowed).map(code=>({code,name:moduleNames[code],level:grants[code].level,message:'Permissão ativa. Os indicadores deste módulo serão conectados quando sua base operacional estiver disponível.'}));
  await audit(request,session,'hierarchy.overview.view','church',childId,{modules:codes.filter(code=>grants[code].allowed)});
  return NextResponse.json(result);
}
