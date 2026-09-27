import { env } from 'cloudflare:workers';
import { NextResponse } from 'next/server';
import { audit, authorize } from '../_auth';

const types=['headquarters','campus','congregation','regional','affiliate'];
const slug=(value:string)=>value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'');

async function ensureHeadquarters(churchId:string){
 const church=await env.DB.prepare('SELECT name,senior_pastor_name FROM churches WHERE id=?').bind(churchId).first<Record<string,string>>();
 const id=churchId==='vinha-demo'?'unit-headquarters':`unit-${churchId}`;
 await env.DB.prepare(`INSERT OR IGNORE INTO church_units (id,church_id,parent_unit_id,name,type,slug,pastor_name,financial_autonomy,communication_autonomy,branding_autonomy,status,created_at) VALUES (?,?,?,?,'headquarters','sede',?,1,1,1,'active',?)`).bind(id,churchId,null,church?.name||'Igreja Central',church?.senior_pastor_name||'Pastor titular',Date.now()).run();
}

export async function GET(request:Request){
 const auth=await authorize(request,'units.read');if(auth.response)return auth.response;const churchId=auth.session!.churchId;await ensureHeadquarters(churchId);
 const isGlobal=['admin','pastor'].includes(auth.session!.role);
 const query=isGlobal
  ? env.DB.prepare(`SELECT u.*,'manager' access_role,1 include_children FROM church_units u WHERE u.church_id=? AND u.status!='archived' ORDER BY CASE u.type WHEN 'headquarters' THEN 0 WHEN 'regional' THEN 1 ELSE 2 END,u.name`).bind(churchId)
  : env.DB.prepare(`WITH RECURSIVE permitted(id,access_role,include_children) AS (
      SELECT unit_id,role,include_children FROM user_unit_access WHERE church_id=? AND user_id=?
      UNION ALL
      SELECT child.id,permitted.access_role,permitted.include_children FROM church_units child JOIN permitted ON child.parent_unit_id=permitted.id WHERE permitted.include_children=1 AND child.church_id=?
    ) SELECT DISTINCT u.*,permitted.access_role,permitted.include_children FROM church_units u JOIN permitted ON permitted.id=u.id WHERE u.church_id=? AND u.status!='archived' ORDER BY CASE u.type WHEN 'headquarters' THEN 0 WHEN 'regional' THEN 1 ELSE 2 END,u.name`).bind(churchId,auth.session!.id,churchId,churchId);
 const rows=await query.all();return NextResponse.json({units:rows.results,currentUser:auth.session,canManage:['admin','pastor'].includes(auth.session!.role)});
}

export async function POST(request:Request){
 const auth=await authorize(request,'units.manage');if(auth.response)return auth.response;const churchId=auth.session!.churchId,d=await request.json<Record<string,string|boolean>>();
 const name=String(d.name||'').trim(),type=String(d.type||'campus');if(!name||!types.includes(type))return NextResponse.json({error:'Nome e tipo de unidade são obrigatórios.'},{status:400});
 if(type!=='headquarters'&&!d.parentUnitId)return NextResponse.json({error:'Selecione a unidade responsável.'},{status:400});
 const id=crypto.randomUUID(),now=Date.now(),unitSlug=`${slug(name)}-${id.slice(0,6)}`;
 await env.DB.prepare(`INSERT INTO church_units (id,church_id,parent_unit_id,name,type,slug,legal_name,tax_id,pastor_name,email,phone,city,state,financial_autonomy,communication_autonomy,branding_autonomy,status,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'active',?)`).bind(id,churchId,d.parentUnitId||null,name,type,unitSlug,d.legalName||null,d.taxId||null,d.pastorName||null,d.email||null,d.phone||null,d.city||null,d.state||null,d.financialAutonomy?1:0,d.communicationAutonomy===false?0:1,d.brandingAutonomy?1:0,now).run();
 await audit(request,auth.session!,'unit.created','church_unit',id,{name,type,parentUnitId:d.parentUnitId||null});return NextResponse.json({id},{status:201});
}

export async function PATCH(request:Request){
 const auth=await authorize(request,'units.manage');if(auth.response)return auth.response;const churchId=auth.session!.churchId,d=await request.json<Record<string,string|boolean>>();
 if(!d.id||!d.name)return NextResponse.json({error:'Unidade inválida.'},{status:400});
 await env.DB.prepare(`UPDATE church_units SET parent_unit_id=?,name=?,type=?,legal_name=?,tax_id=?,pastor_name=?,email=?,phone=?,city=?,state=?,financial_autonomy=?,communication_autonomy=?,branding_autonomy=? WHERE id=? AND church_id=?`).bind(d.parentUnitId||null,d.name,d.type||'campus',d.legalName||null,d.taxId||null,d.pastorName||null,d.email||null,d.phone||null,d.city||null,d.state||null,d.financialAutonomy?1:0,d.communicationAutonomy===false?0:1,d.brandingAutonomy?1:0,d.id,churchId).run();
 await audit(request,auth.session!,'unit.updated','church_unit',String(d.id),{name:d.name});return NextResponse.json({ok:true});
}
