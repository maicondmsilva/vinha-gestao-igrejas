import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {boundedChurchJson} from '../../lib/church-json';
import {plusUuid,plusDate} from '../../lib/cell-plus';
import type {OperationsClient} from '../../lib/supabase/operations';
const json=(d:unknown,status=200)=>NextResponse.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
export async function GET(r:Request){const a=await authorizeSupabaseChurch(r,'units.read');if(!a||a.response)return a?.response||json({error:'Acesso indisponível.'},503);return json({units:a.access!.membership.units.map(u=>({id:u.id,name:u.name}))})}
export async function POST(r:Request){const a=await authorizeSupabaseChurch(r,'units.read');if(!a||a.response)return a?.response||json({error:'Acesso indisponível.'},503);
 try{const d=await boundedChurchJson(r,16384) as Record<string,unknown>;if(!d||Object.keys(d).sort().join(',')!=='from,to,units'||!Array.isArray(d.units)||d.units.length<1||d.units.length>100)throw Error();
 const units=d.units.map(plusUuid),from=plusDate(d.from),to=plusDate(d.to);if(new Set(units).size!==units.length||units.some(id=>!a.access!.membership.units.some(u=>u.id===id))||to<from||Date.parse(to)-Date.parse(from)>366*86400000)return json({error:'Selecione apenas unidades autorizadas e um período de até 366 dias.'},400);
 const {data,error}=await (a.access!.client as unknown as OperationsClient).rpc('cell_consolidated',{p_org:a.access!.membership.organization_id,p_units:units,p_from:from,p_to:to});
 if(error)return json({error:'Uma das unidades não está autorizada para consultar Células ou está bloqueada. Ajuste a seleção.'},error.code==='42501'?403:503);
 if(!data||data.from!==from||data.to!==to||!Array.isArray(data.units)||data.units.length!==units.length||data.units.some((u:{unitId:string})=>!units.includes(u.unitId)))return json({error:'Resposta divergente.'},503);
 return json(data);
 }catch{return json({error:'Seleção inválida.'},400)}
}
