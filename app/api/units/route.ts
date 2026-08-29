import { env } from 'cloudflare:workers';
import { NextResponse } from 'next/server';
import { audit, authorize, CHURCH_ID } from '../_auth';

const types=['headquarters','campus','congregation','regional','affiliate'];
const slug=(value:string)=>value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'');

async function ensureHeadquarters(){
 const church=await env.DB.prepare('SELECT name,senior_pastor_name FROM churches WHERE id=?').bind(CHURCH_ID).first<Record<string,string>>();
 await env.DB.prepare(`INSERT OR IGNORE INTO church_units (id,church_id,parent_unit_id,name,type,slug,pastor_name,financial_autonomy,communication_autonomy,branding_autonomy,status,created_at) VALUES ('unit-headquarters',?,?,?,'headquarters','sede',?,1,1,1,'active',?)`).bind(CHURCH_ID,null,church?.name||'Igreja Central',church?.senior_pastor_name||'Pastor titular',Date.now()).run();
}

export async function GET(request:Request){
 const auth=await authorize(request,'units.read');if(auth.response)return auth.response;await ensureHeadquarters();
 const isGlobal=['admin','pastor'].includes(auth.session!.role);
 const query=isGlobal
  ? env.DB.prepare(`SELECT u.*,'manager' access_role,1 include_children FROM church_units u WHERE u.church_id=? AND u.status!='archived' ORDER BY CASE u.type WHEN 'headquarters' THEN 0 WHEN 'regional' THEN 1 ELSE 2 END,u.name`).bind(CHURCH_ID)
  : env.DB.prepare(`SELECT DISTINCT u.*,a.role access_role,a.include_children FROM church_units u JOIN user_unit_access a ON a.unit_id=u.id AND a.church_id=u.church_id WHERE u.church_id=? AND a.user_id=? AND u.status!='archived' ORDER BY u.name`).bind(CHURCH_ID,auth.session!.id);
 const rows=await query.all();return NextResponse.json({units:rows.results,currentUser:auth.session,canManage:['admin','pastor'].includes(auth.session!.role)});
}

export async function POST(request:Request){
 const auth=await authorize(request,'units.manage');if(auth.response)return auth.response;const d=await request.json<Record<string,string|boolean>>();
 const name=String(d.name||'').trim(),type=String(d.type||'campus');if(!name||!types.includes(type))return NextResponse.json({error:'Nome e tipo de unidade são obrigatórios.'},{status:400});
 if(type!=='headquarters'&&!d.parentUnitId)return NextResponse.json({error:'Selecione a unidade responsável.'},{status:400});
 const id=crypto.randomUUID(),now=Date.now(),unitSlug=`${slug(name)}-${id.slice(0,6)}`;
 await env.DB.prepare(`INSERT INTO church_units (id,church_id,parent_unit_id,name,type,slug,legal_name,tax_id,pastor_name,email,phone,city,state,financial_autonomy,communication_autonomy,branding_autonomy,status,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'active',?)`).bind(id,CHURCH_ID,d.parentUnitId||null,name,type,unitSlug,d.legalName||null,d.taxId||null,d.pastorName||null,d.email||null,d.phone||null,d.city||null,d.state||null,d.financialAutonomy?1:0,d.communicationAutonomy===false?0:1,d.brandingAutonomy?1:0,now).run();
 await audit(request,auth.session!,'unit.created','church_unit',id,{name,type,parentUnitId:d.parentUnitId||null});return NextResponse.json({id},{status:201});
}

export async function PATCH(request:Request){
 const auth=await authorize(request,'units.manage');if(auth.response)return auth.response;const d=await request.json<Record<string,string|boolean>>();
 if(!d.id||!d.name)return NextResponse.json({error:'Unidade inválida.'},{status:400});
 await env.DB.prepare(`UPDATE church_units SET parent_unit_id=?,name=?,type=?,legal_name=?,tax_id=?,pastor_name=?,email=?,phone=?,city=?,state=?,financial_autonomy=?,communication_autonomy=?,branding_autonomy=? WHERE id=? AND church_id=?`).bind(d.parentUnitId||null,d.name,d.type||'campus',d.legalName||null,d.taxId||null,d.pastorName||null,d.email||null,d.phone||null,d.city||null,d.state||null,d.financialAutonomy?1:0,d.communicationAutonomy===false?0:1,d.brandingAutonomy?1:0,d.id,CHURCH_ID).run();
 await audit(request,auth.session!,'unit.updated','church_unit',String(d.id),{name:d.name});return NextResponse.json({ok:true});
}
