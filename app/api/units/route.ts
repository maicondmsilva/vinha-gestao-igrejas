import { NextResponse } from 'next/server';
import {authorizeSupabaseChurch,supabaseAudit} from '../../lib/supabase/church-access';

import {validUnitParent} from '../../lib/unit-integrity';
import {unitWriteError} from '../../lib/unit-write-error';

const types=['headquarters','campus','congregation','regional','affiliate'];
const slug=(value:string)=>value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'');

const pgType=(value:string)=>value==='affiliate'?'branch':value;
const uiType=(value:string)=>value==='branch'?'affiliate':value;

async function supabaseGET(request:Request){
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Supabase indisponível.'},{status:503});
 const access=auth.access!,organizationId=access.membership.organization_id;
 const allowedIds=access.membership.units.map(unit=>unit.id);
 const {data,error}=allowedIds.length?await access.client.from('organization_units').select('*').eq('organization_id',organizationId).in('id',allowedIds).eq('status','active').order('name'):{data:[],error:null};
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
 const parentId=d.parentUnitId?String(d.parentUnitId):null;
 if(parentId){
  const {data:parent,error:parentError}=await access.client.from('organization_units').select('id').eq('organization_id',organizationId).eq('id',parentId).eq('status','active').maybeSingle();
  if(parentError)return NextResponse.json({error:'Não foi possível validar a unidade responsável.'},{status:503});
  if(!parent)return NextResponse.json({error:'Unidade responsável inválida ou sem acesso.'},{status:400});
 }
 const {data,error}=await access.client.from('organization_units').insert({organization_id:organizationId,parent_unit_id:d.parentUnitId?String(d.parentUnitId):null,name,unit_type:pgType(type) as 'headquarters'|'regional'|'campus'|'congregation'|'branch',slug:unitSlug,legal_name:d.legalName?String(d.legalName):null,tax_id:d.taxId?String(d.taxId):null,pastor_name:d.pastorName?String(d.pastorName):null,email:d.email?String(d.email):null,phone:d.phone?String(d.phone):null,address:{city:String(d.city||''),state:String(d.state||'')},financial_autonomy:Boolean(d.financialAutonomy),communication_autonomy:d.communicationAutonomy!==false,branding_autonomy:Boolean(d.brandingAutonomy),status:'active'}).select('id').single();
 if(error||!data)return NextResponse.json({error:unitWriteError(error?.message,'Não foi possível cadastrar a unidade.')},{status:400});
 await supabaseAudit(request,access,'unit.created','organization_unit',data.id,{name,type,parentUnitId:d.parentUnitId||null});return NextResponse.json({id:data.id},{status:201});
}

async function supabasePATCH(request:Request){
 const auth=await authorizeSupabaseChurch(request,'units.manage');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Supabase indisponível.'},{status:503});
 const access=auth.access!,d=await request.json<Record<string,string|boolean>>();if(!d.id||!d.name)return NextResponse.json({error:'Unidade inválida.'},{status:400});
 const organizationId=access.membership.organization_id;
 const {data:existing,error:readError}=await access.client.from('organization_units').select('id,name,parent_unit_id,unit_type').eq('organization_id',organizationId).eq('status','active');
 if(readError)return NextResponse.json({error:'Não foi possível validar a hierarquia.'},{status:503});
 const current=(existing||[]).find(unit=>unit.id===String(d.id));
 if(!current)return NextResponse.json({error:'Unidade não encontrada ou sem acesso.'},{status:404});
 const type=d.type===undefined?uiType(current.unit_type||'campus'):String(d.type);
 if(!types.includes(type))return NextResponse.json({error:'Tipo de unidade inválido.'},{status:400});
 const parentId=d.parentUnitId===undefined?current.parent_unit_id:d.parentUnitId?String(d.parentUnitId):null;
 if((type!=='headquarters'&&!parentId)||!validUnitParent(existing||[],String(d.id),parentId))return NextResponse.json({error:'Unidade responsável inválida ou vínculo circular na hierarquia.'},{status:400});
 const {data:updated,error}=await access.client.from('organization_units').update({parent_unit_id:parentId,name:String(d.name),unit_type:pgType(type) as 'headquarters'|'regional'|'campus'|'congregation'|'branch',legal_name:d.legalName?String(d.legalName):null,tax_id:d.taxId?String(d.taxId):null,pastor_name:d.pastorName?String(d.pastorName):null,email:d.email?String(d.email):null,phone:d.phone?String(d.phone):null,address:{city:String(d.city||''),state:String(d.state||'')},financial_autonomy:Boolean(d.financialAutonomy),communication_autonomy:d.communicationAutonomy!==false,branding_autonomy:Boolean(d.brandingAutonomy)}).eq('id',String(d.id)).eq('organization_id',organizationId).select('id').maybeSingle();
 if(error)return NextResponse.json({error:unitWriteError(error.message,'Não foi possível atualizar a unidade.')},{status:400});
 if(!updated)return NextResponse.json({error:'Unidade não encontrada ou sem permissão para editar.'},{status:404});
 await supabaseAudit(request,access,'unit.updated','organization_unit',String(d.id),{name:d.name});return NextResponse.json({ok:true});
}

export {supabaseGET as GET,supabasePOST as POST,supabasePATCH as PATCH};
