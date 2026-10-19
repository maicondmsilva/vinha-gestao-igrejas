import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import type {OperationsClient} from '../../lib/supabase/operations';
import {boundedChurchJson,exactKeys} from '../../lib/church-json';
import {languageLabels,languageState} from '../../lib/ministry-language';
const headers={'Cache-Control':'private, no-store'};
export async function GET(request:Request){return handle(request,false)}
export async function POST(request:Request){return handle(request,true)}
async function handle(request:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(request,'units.read');if(!auth||auth.response)return auth?.response||NextResponse.json({error:'Acesso indisponível.'},{status:503,headers});
 try{
  const access=auth.access!,client=access.client as unknown as OperationsClient;
  let args:Record<string,unknown>={p_organization:access.membership.organization_id};
  if(write){try{const body=await boundedChurchJson(request,8192);exactKeys(body,['version','labels']);if(!Number.isSafeInteger(body.version)||Number(body.version)<0)throw Error();args={...args,p_version:body.version,p_labels:languageLabels(body.labels)}}catch{return NextResponse.json({error:'Revise os nomes informados.'},{status:400,headers})}}
  const {data,error}=await client.rpc(write?'ministry_language_save':'ministry_language_read',args);
  if(error)return NextResponse.json({error:error.code==='42501'?'Somente proprietários e administradores autorizados podem personalizar o ministério.':error.code==='40001'?'Os nomes foram alterados por outra pessoa. Atualize antes de salvar.':'Não foi possível carregar ou salvar os nomes.'},{status:error.code==='42501'?403:error.code==='40001'?409:503,headers});
  const result=languageState(data);if(result.organizationId!==access.membership.organization_id)throw Error();return NextResponse.json(result,{headers});
 }catch{return NextResponse.json({error:'Personalização temporariamente indisponível.'},{status:503,headers})}
}
