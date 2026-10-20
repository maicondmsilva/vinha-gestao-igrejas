import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {boundedChurchJson} from '../../lib/church-json';
import {plusUuid} from '../../lib/cell-plus';
import type {OperationsClient} from '../../lib/supabase/operations';
import {cellDeliveryConfig} from '../../lib/supabase/cell-deliveries';
const json=(d:unknown,status=200)=>NextResponse.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
export async function GET(r:Request){return handle(r,false)}
export async function POST(r:Request){return handle(r,true)}
async function handle(r:Request,write:boolean){const auth=await authorizeSupabaseChurch(r,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);
 try{const a=auth.access!,p=new URL(r.url).searchParams;if(p.getAll('unitId').length!==1)throw Error();const unit=plusUuid(p.get('unitId'));if(!a.membership.units.some(u=>u.id===unit))return json({error:'Unidade sem acesso.'},403);
 let args:Record<string,unknown>={p_org:a.membership.organization_id,p_unit:unit};if(write){const d=await boundedChurchJson(r,4096) as Record<string,unknown>;if(!d||Object.keys(d).sort().join(',')!=='emailEnabled,version,whatsappEnabled'||typeof d.emailEnabled!=='boolean'||typeof d.whatsappEnabled!=='boolean'||!Number.isSafeInteger(d.version)||Number(d.version)<0)throw Error();args={...args,p_email:d.emailEnabled,p_whatsapp:d.whatsappEnabled,p_version:d.version}}
 const {data,error}=await (a.client as unknown as OperationsClient).rpc('cell_delivery_preferences',args);if(error)return json({error:error.code==='22023'?'WhatsApp exige telefone confirmado na sua conta.':error.code==='40001'?'Preferências alteradas. Atualize antes de salvar.':'Não foi possível validar as preferências.'},error.code==='40001'?409:403);
 return json({...data,channels:cellDeliveryConfig(process.env)});
 }catch{return json({error:'Preferências inválidas.'},400)}
}
