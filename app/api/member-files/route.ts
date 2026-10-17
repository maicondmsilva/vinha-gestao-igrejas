import {randomUUID} from 'node:crypto';
import {NextResponse} from 'next/server';
import {authorizeSupabaseChurch} from '../../lib/supabase/church-access';
import {boundedBody,detectedFile,memberFilePath,privateFileLimit,uuidPattern} from '../../lib/private-files';
const bucket='member-private';
const json=(body:unknown,status=200)=>NextResponse.json(body,{status,headers:{'Cache-Control':'no-store, private'}});
export async function GET(request:Request){
 const auth=await authorizeSupabaseChurch(request,'people.read');if(!auth||auth.response)return auth?.response||json({error:'Serviço indisponível.'},503);
 const a=auth.access!,url=new URL(request.url),person=url.searchParams.get('person')||'',file=url.searchParams.get('file');
 if(!uuidPattern.test(person))return json({error:'Cadastro inválido.'},400);
 const {data,error}=await a.client.from('people').select('id').eq('organization_id',a.membership.organization_id).eq('id',person).maybeSingle();
 if(error)return json({error:'Não foi possível verificar o cadastro.'},503);if(!data)return json({error:'Cadastro não encontrado ou sem acesso.'},404);
 if(file){
  const path=memberFilePath(a.membership.organization_id,person,file);if(!path)return json({error:'Arquivo inválido.'},400);
  const result=await a.client.storage.from(bucket).download(path);if(result.error||!result.data)return json({error:'Arquivo não encontrado ou sem acesso.'},404);
  return new Response(result.data,{headers:{'Content-Type':'application/octet-stream','Content-Disposition':`attachment; filename="${file}"`,'X-Content-Type-Options':'nosniff','Cache-Control':'no-store, private'}});
 }
 const result=await a.client.storage.from(bucket).list(`${a.membership.organization_id}/${person}`,{limit:100,sortBy:{column:'created_at',order:'desc'}});
 if(result.error)return json({error:'Não foi possível carregar os arquivos privados.'},503);
 return json({items:(result.data||[]).filter(x=>memberFilePath(a.membership.organization_id,person,x.name)).map(x=>({name:x.name,createdAt:x.created_at,size:x.metadata?.size||0})),limit:100});
}
export async function POST(request:Request){
 const auth=await authorizeSupabaseChurch(request,'people.write');if(!auth||auth.response)return auth?.response||json({error:'Serviço indisponível.'},503);
 try{
  const a=auth.access!,bytes=await boundedBody(request,privateFileLimit+65536);
  const form=await new Request(request.url,{method:'POST',headers:{'Content-Type':request.headers.get('content-type')||''},body:bytes}).formData();
  const person=String(form.get('person')||''),file=form.get('file');
  if(!uuidPattern.test(person)||!(file instanceof File)||file.size===0)return json({error:'Escolha um cadastro e um arquivo válido.'},400);
  if(file.size>privateFileLimit)return json({error:'O limite por arquivo é 4 MB.'},413);
  const content=new Uint8Array(await file.arrayBuffer()),kind=detectedFile(content);if(!kind)return json({error:'Envie somente PDF, PNG ou JPEG válido.'},400);
  const path=memberFilePath(a.membership.organization_id,person,`${randomUUID()}.${kind.extension}`);if(!path)return json({error:'Arquivo inválido.'},400);
  const {data:target,error}=await a.client.from('people').select('id').eq('organization_id',a.membership.organization_id).eq('id',person).maybeSingle();
  if(error)return json({error:'Não foi possível verificar o cadastro.'},503);if(!target)return json({error:'Cadastro não encontrado ou sem acesso.'},404);
  const result=await a.client.storage.from(bucket).upload(path,content,{contentType:kind.mime,upsert:false,cacheControl:'0'});
  if(result.error||!result.data?.path)return json({error:'Não foi possível confirmar o envio. Atualize a lista antes de tentar novamente.'},503);
  return json({ok:true,name:path.split('/').at(-1)},201);
 }catch(e){return json({error:e instanceof Error&&e.message==='body_too_large'?'Arquivo maior que o limite permitido.':'Não foi possível enviar o arquivo.'},e instanceof Error&&e.message==='body_too_large'?413:400)}
}
