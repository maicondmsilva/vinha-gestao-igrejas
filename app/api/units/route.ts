import { env } from 'cloudflare:workers';
import { NextResponse } from 'next/server';
import { audit, authorize } from '../_auth';
import {authorizeSupabaseChurch,supabaseAudit} from '../../lib/supabase/church-access';
import {supabaseServerConfigured} from '../../lib/supabase/request';

const types=['headquarters','campus','congregation','regional','affiliate'];
const slug=(value:string)=>value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'');

const pgType=(value:string)=>value==='affiliate'?'branch':value;
const uiType=(value:string)=>value==='branch'?'affiliate':value;

async function supabaseGET(request:Request){
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Supabase indisponível.'},{status:503});
 const access=auth.access!,organizationId=access.membership.organization_id;
 const {data,error}=await access.client.from('organization_units').select('*').eq('organization_id',organizationId).eq('status','active').order('name');
 if(error)return NextResponse.json({error:'Não foi possível carregar as unidades.'},{status:500});
 const units=(data||[]).sort((a,b)=>{const order=(type:string)=>type==='headquarters'?0:type==='regional'?1:2;return order(a.unit_type)-order(b.unit_type)||a.name.localeCompare(b.name,'pt-BR')}).map(unit=>({
  ...unit,type:uiType(unit.unit_type),church_id:unit.organization_id,city:typeof unit.address==='object'&& unit.address!==null&&!Array.isArray(unit.address)?String((unit.address as Record<string,unknown>).city||''):'',state:typeof unit.address==='object'&&unit.address!==null&&!Array.isArray(unit.address)?String((unit.address as Record<string,unknown>).state||''):'',
  financial_autonomy:unit.financial_autonomy?1:0,communication_autonomy:unit.communication_autonomy?1:0,branding_autonomy:unit.branding_autonomy?1:0,access_role:['owner','pastor','admin'].includes(access.membership.role)?'manager':'viewer',include_children:1,
 }));
 return NextResponse.json({units,currentUser:{id:access.membership.membership_id,churchId:organizationId,churchSlug:access.membership.organization_slug,email:access.email,role:access.membership.role},canManage:access.can('units.manage')});
}

async function supabasePOST(request:Request){
 const auth=await authorizeSupabaseChurch(request,'units.manage');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Supabase indisponível.'},{status:503});
 const access=auth.access!,d=await request.json<Record<string,string|boolean>>(),name=String(d.name||'').trim(),type=String(d.type||'campus');
 if(!name||!types.includes(type))return NextResponse.json({error:'Nome e tipo de unidade são obrigatórios.'},{status:400});
 if(type!=='headquarters'&&!d.parentUnitId)return NextResponse.json({error:'Selecione a unidade responsável.'},{status:400});
 const organizationId=access.membership.organization_id,unitSlug=`${slug(name)}-${crypto.randomUUID().slice(0,6)}`;
 const {data,error}=await access.client.from('organization_units').insert({organization_id:organizationId,parent_unit_id:d.parentUnitId?String(d.parentUnitId):null,name,unit_type:pgType(type) as 'headquarters'|'regional'|'campus'|'congregation'|'branch',slug:unitSlug,legal_name:d.legalName?String(d.legalName):null,tax_id:d.taxId?String(d.taxId):null,pastor_name:d.pastorName?String(d.pastorName):null,email:d.email?String(d.email):null,phone:d.phone?String(d.phone):null,address:{city:String(d.city||''),state:String(d.state||'')},financial_autonomy:Boolean(d.financialAutonomy),communication_autonomy:d.communicationAutonomy!==false,branding_autonomy:Boolean(d.brandingAutonomy),status:'active'}).select('id').single();
 if(error||!data)return NextResponse.json({error:'Não foi possível cadastrar a unidade.'},{status:400});
 await supabaseAudit(request,access,'unit.created','organization_unit',data.id,{name,type,parentUnitId:d.parentUnitId||null});return NextResponse.json({id:data.id},{status:201});
}

async function supabasePATCH(request:Request){
 const auth=await authorizeSupabaseChurch(request,'units.manage');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Supabase indisponível.'},{status:503});
 const access=auth.access!,d=await request.json<Record<string,string|boolean>>();if(!d.id||!d.name)return NextResponse.json({error:'Unidade inválida.'},{status:400});
 const type=String(d.type||'campus');if(!types.includes(type))return NextResponse.json({error:'Tipo de unidade inválido.'},{status:400});
 const {error}=await access.client.from('organization_units').update({parent_unit_id:d.parentUnitId?String(d.parentUnitId):null,name:String(d.name),unit_type:pgType(type) as 'headquarters'|'regional'|'campus'|'congregation'|'branch',legal_name:d.legalName?String(d.legalName):null,tax_id:d.taxId?String(d.taxId):null,pastor_name:d.pastorName?String(d.pastorName):null,email:d.email?String(d.email):null,phone:d.phone?String(d.phone):null,address:{city:String(d.city||''),state:String(d.state||'')},financial_autonomy:Boolean(d.financialAutonomy),communication_autonomy:d.communicationAutonomy!==false,branding_autonomy:Boolean(d.brandingAutonomy)}).eq('id',String(d.id)).eq('organization_id',access.membership.organization_id);
 if(error)return NextResponse.json({error:'Não foi possível atualizar a unidade.'},{status:400});
 await supabaseAudit(request,access,'unit.updated','organization_unit',String(d.id),{name:d.name});return NextResponse.json({ok:true});
}

async function ensureHeadquarters(churchId:string){
 const church=await env.DB.prepare('SELECT name,senior_pastor_name FROM churches WHERE id=?').bind(churchId).first<Record<string,string>>();
 const id=churchId==='vinha-demo'?'unit-headquarters':`unit-${churchId}`;
 await env.DB.prepare(`INSERT OR IGNORE INTO church_units (id,church_id,parent_unit_id,name,type,slug,pastor_name,financial_autonomy,communication_autonomy,branding_autonomy,status,created_at) VALUES (?,?,?,?,'headquarters','sede',?,1,1,1,'active',?)`).bind(id,churchId,null,church?.name||'Igreja Central',church?.senior_pastor_name||'Pastor titular',Date.now()).run();
}

async function legacyGET(request:Request){
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

async function legacyPOST(request:Request){
 const auth=await authorize(request,'units.manage');if(auth.response)return auth.response;const churchId=auth.session!.churchId,d=await request.json<Record<string,string|boolean>>();
 const name=String(d.name||'').trim(),type=String(d.type||'campus');if(!name||!types.includes(type))return NextResponse.json({error:'Nome e tipo de unidade são obrigatórios.'},{status:400});
 if(type!=='headquarters'&&!d.parentUnitId)return NextResponse.json({error:'Selecione a unidade responsável.'},{status:400});
 const id=crypto.randomUUID(),now=Date.now(),unitSlug=`${slug(name)}-${id.slice(0,6)}`;
 await env.DB.prepare(`INSERT INTO church_units (id,church_id,parent_unit_id,name,type,slug,legal_name,tax_id,pastor_name,email,phone,city,state,financial_autonomy,communication_autonomy,branding_autonomy,status,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'active',?)`).bind(id,churchId,d.parentUnitId||null,name,type,unitSlug,d.legalName||null,d.taxId||null,d.pastorName||null,d.email||null,d.phone||null,d.city||null,d.state||null,d.financialAutonomy?1:0,d.communicationAutonomy===false?0:1,d.brandingAutonomy?1:0,now).run();
 await audit(request,auth.session!,'unit.created','church_unit',id,{name,type,parentUnitId:d.parentUnitId||null});return NextResponse.json({id},{status:201});
}

async function legacyPATCH(request:Request){
 const auth=await authorize(request,'units.manage');if(auth.response)return auth.response;const churchId=auth.session!.churchId,d=await request.json<Record<string,string|boolean>>();
 if(!d.id||!d.name)return NextResponse.json({error:'Unidade inválida.'},{status:400});
 await env.DB.prepare(`UPDATE church_units SET parent_unit_id=?,name=?,type=?,legal_name=?,tax_id=?,pastor_name=?,email=?,phone=?,city=?,state=?,financial_autonomy=?,communication_autonomy=?,branding_autonomy=? WHERE id=? AND church_id=?`).bind(d.parentUnitId||null,d.name,d.type||'campus',d.legalName||null,d.taxId||null,d.pastorName||null,d.email||null,d.phone||null,d.city||null,d.state||null,d.financialAutonomy?1:0,d.communicationAutonomy===false?0:1,d.brandingAutonomy?1:0,d.id,churchId).run();
 await audit(request,auth.session!,'unit.updated','church_unit',String(d.id),{name:d.name});return NextResponse.json({ok:true});
}

export async function GET(request:Request){return supabaseServerConfigured?supabaseGET(request):legacyGET(request)}
export async function POST(request:Request){return supabaseServerConfigured?supabasePOST(request):legacyPOST(request)}
export async function PATCH(request:Request){return supabaseServerConfigured?supabasePATCH(request):legacyPATCH(request)}
