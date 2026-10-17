import {createHash} from 'node:crypto';
import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {resolveUnitSelection} from '../../../lib/unit-integrity';
import {validateImportRows} from '../../../lib/member-import';
import type {Json} from '../../../lib/supabase/database.types';

type ImportClient={from:(table:string)=>any;rpc:(name:string,args:Record<string,unknown>)=>Promise<{data:any;error:{code?:string}|null}>};
function failure(code?:string){
 const status=code==='42501'||code==='28000'?403:code==='22023'?400:503;
 return NextResponse.json({error:status===403?'Você não pode importar nesta unidade ou o módulo está bloqueado.':status===400?'Revise a planilha, a unidade e o lote. Nenhum dado deste lote foi alterado.':'Não foi possível confirmar o lote. Use Tentar novamente; o mesmo lote não será importado duas vezes.'},{status,headers:{'Cache-Control':'no-store'}});
}
export async function GET(request:Request){
 const auth=await authorizeSupabaseChurch(request,'people.write');if(!auth||auth.response)return auth?.response||failure();
 const access=auth.access!,client=access.client as unknown as ImportClient;
 const {data,error}=await client.from('member_import_receipts').select('id,file_name,result,created_at').eq('organization_id',access.membership.organization_id).eq('created_by',access.userId).order('created_at',{ascending:false}).limit(10);
 if(error)return failure(error.code);
 return NextResponse.json({jobs:(data||[]).map((item:any)=>({id:item.id,file_name:item.file_name,total_rows:item.result.total,imported_rows:item.result.imported,skipped_rows:item.result.skipped,error_rows:item.result.invalid,status:'completed',created_at:item.created_at})),units:access.membership.units,defaultUnitId:access.membership.default_unit_id},{headers:{'Cache-Control':'no-store'}});
}
export async function POST(request:Request){
 const auth=await authorizeSupabaseChurch(request,'people.write');if(!auth||auth.response)return auth?.response||failure();
 const access=auth.access!,client=access.client as unknown as ImportClient;
 let body:Record<string,unknown>;let checked:ReturnType<typeof validateImportRows>;
 try{
  const raw=await request.text();if(raw.length>524288)return NextResponse.json({error:'Arquivo excede o limite de 512 KB por solicitação.'},{status:413});
  body=JSON.parse(raw);if(!body||typeof body!=='object'||Array.isArray(body))throw new Error('Solicitação inválida.');
  if(body.mode!=='preview'&&body.mode!=='commit')throw new Error('Escolha validar ou importar.');
  checked=validateImportRows(body.rows);
  if(body.mode==='commit'&&(checked.length>100||checked.some(item=>item.errors.length)))throw new Error('Valide a planilha e envie até 100 linhas válidas por lote.');
 }catch(error){return NextResponse.json({error:error instanceof Error?error.message:'Planilha inválida.'},{status:400})}
 const {data:units,error:unitError}=await client.from('organization_units').select('id,name').eq('organization_id',access.membership.organization_id).eq('status','active');
 if(unitError)return failure();
 if(body.unitId!==undefined&&typeof body.unitId!=='string')return NextResponse.json({error:'Selecione uma unidade válida.'},{status:400});
 const unitId=resolveUnitSelection(units||[],body.unitId as string|undefined,access.membership.default_unit_id);
 if(!unitId)return NextResponse.json({error:'Selecione uma unidade ativa e autorizada.'},{status:400});
 const rows=checked.map(item=>item.row);
 // Stable content identity also protects re-uploading a name-only CSV after a lost response.
 const hash=createHash('sha256').update(JSON.stringify([access.membership.organization_id,access.userId,unitId,rows])).digest('hex');
 const requestId=`${hash.slice(0,8)}-${hash.slice(8,12)}-${hash.slice(12,16)}-${hash.slice(16,20)}-${hash.slice(20,32)}`;
 const {data,error}=await client.rpc('import_member_batch',{p_organization:access.membership.organization_id,p_unit:unitId,p_rows:rows as unknown as Json,p_mode:body.mode,p_request:body.mode==='commit'?requestId:null,p_file:typeof body.fileName==='string'?body.fileName.slice(0,180):'membros.csv'});
 if(error)return failure(error.code);if(!data||typeof data!=='object')return failure();
 if(body.mode==='preview'){
  if(!Array.isArray(data.rows)||data.rows.length!==checked.length)return failure();
  const previewRows=data.rows.map((item:any,index:number)=>({...item,line:checked[index].line,errors:Array.from(new Set([...checked[index].errors,...(Array.isArray(item.errors)?item.errors:[])]))}));
  return NextResponse.json({...data,rows:previewRows,valid:previewRows.filter((item:any)=>!item.errors.length&&!item.duplicate).length,invalid:previewRows.filter((item:any)=>item.errors.length).length,skipped:previewRows.filter((item:any)=>!item.errors.length&&item.duplicate).length,unitId},{headers:{'Cache-Control':'no-store'}});
 }
 if(data.total!==rows.length||typeof data.imported!=='number'||typeof data.skipped!=='number'||typeof data.invalid!=='number'||data.imported+data.skipped+data.invalid!==data.total)return failure();
 return NextResponse.json(data,{headers:{'Cache-Control':'no-store'}});
}
