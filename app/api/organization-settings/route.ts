import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {reportLogo} from '../../lib/finance-export';
import {PDFDocument} from 'pdf-lib';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
export async function GET(request:Request){
 try{
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Serviço indisponível.'},503);
 const a=auth.access!,client=db(request),org=a.membership.organization_id;
 const [profile,brands]=await Promise.all([client.from('organizations').select('id,slug,name,app_name,senior_pastor_name,legal_name,tax_id,primary_color,accent_color,app_theme,updated_at,registration_code').eq('id',org).single(),client.rpc('church_branding_read',{p_org:org})]);
 if(profile.error||brands.error)return json({error:'Não foi possível carregar as configurações.'},503);
 return json({organization:profile.data,brands:brands.data,canManage:a.can('units.manage')||(await client.rpc('permission_any' as never,{p_org:org,p_checks:['church.settings:edit']} as never)).data===true});
 }catch{return json({error:'Não foi possível carregar as configurações.'},503)}
}
export async function PATCH(request:Request){
 try{
 const auth=await authorizeSupabaseChurch(request,'units.manage',['church.settings:edit']);if(!auth||auth.response)return auth?.response||json({error:'Serviço indisponível.'},503);
 let body:{unitId?:string;data?:Record<string,unknown>};
 try{body=JSON.parse(new TextDecoder().decode(await boundedBody(request,350000)));if(!body||Array.isArray(body)||Object.keys(body).some(k=>!['unitId','data'].includes(k))||!body.data||Array.isArray(body.data)||typeof body.data!=='object'||body.unitId&&!uuidPattern.test(body.unitId))throw Error('Revise os dados.');if('logo'in body.data){const bytes=reportLogo(body.data.logo);if(bytes){const pdf=await PDFDocument.create();await pdf.embedPng(bytes)}}}catch{return json({error:'Revise os dados. A logo deve ser PNG de até 250 KB e 2 milhões de pixels.'},400)}
 const a=auth.access!;if(body.unitId&&!a.membership.units.some(u=>u.id===body.unitId))return json({error:'Unidade sem acesso.'},403);
 const result=await db(request).rpc('organization_settings_save',{p_org:a.membership.organization_id,p_unit:body.unitId||null,p_data:body.data});
 if(result.error){const code=result.error.code;return json({error:code==='40001'?'O cadastro foi alterado por outra pessoa. Recarregue antes de salvar.':code==='42501'?'Você não possui autorização para alterar este cadastro.':code==='22023'?'Revise os campos obrigatórios e a logo.':'Não foi possível confirmar o salvamento. Recarregue antes de tentar novamente.'},code==='40001'?409:code==='42501'?403:code==='22023'?400:503)}
 if(result.data?.ok!==true||typeof result.data.updatedAt!=='string')return json({error:'Salvamento não confirmado. Recarregue antes de repetir.'},503);
 return json(result.data);
 }catch{return json({error:'Conexão interrompida. Recarregue para conferir o cadastro antes de repetir.'},503)}
}
