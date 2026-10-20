import {randomUUID} from 'node:crypto';
import {authorizeSupabaseChurch} from '../../../lib/supabase/church-access';
import {boundedBody,detectedFile,privateFileLimit,uuidPattern,memberFilePath} from '../../../lib/private-files';
const bucket='finance-documents-private';
const json=(d:unknown,status=200)=>Response.json(d,{status,headers:{'Cache-Control':'private, no-store'}});
async function handle(r:Request,write:boolean){
 const auth=await authorizeSupabaseChurch(r,'units.read');if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);
 try{const a=auth.access!,p=new URL(r.url).searchParams,unit=p.get('unitId')||'',entry=p.get('entryId')||'';
 if(!['owner','admin','finance'].includes(a.membership.role)||!a.membership.units.some(u=>u.id===unit))return json({error:'Sem acesso financeiro.'},403);
 if(!uuidPattern.test(unit)||!uuidPattern.test(entry)||p.getAll('unitId').length!==1||p.getAll('entryId').length!==1)return json({error:'Escopo inválido.'},400);
 const prefix=`${a.membership.organization_id}/${unit}/${entry}`;
 if(write){
  const bytes=await boundedBody(r,privateFileLimit+65536),form=await new Request(r.url,{method:'POST',headers:{'Content-Type':r.headers.get('content-type')||''},body:bytes}).formData(),file=form.get('file');
  if(!(file instanceof File)||!file.size||file.size>privateFileLimit)return json({error:'Envie um arquivo de até 4 MB.'},400);
  const content=new Uint8Array(await file.arrayBuffer()),kind=detectedFile(content);if(!kind)return json({error:'Envie PDF, PNG ou JPEG válido.'},400);
  const name=`${randomUUID()}.${kind.extension}`,result=await a.client.storage.from(bucket).upload(`${prefix}/${name}`,content,{contentType:kind.mime,upsert:false,cacheControl:'0'});
  if(result.error)return json({error:'Envio não confirmado ou sem permissão. Consulte a lista antes de repetir.'},403);
  return json({name},201);
 }
 const file=p.get('file');if(file){if(!memberFilePath(a.membership.organization_id,entry,file))return json({error:'Arquivo inválido.'},400);
  const result=await a.client.storage.from(bucket).download(`${prefix}/${file}`);if(result.error||!result.data)return json({error:'Arquivo não encontrado ou sem acesso atual.'},404);
  return new Response(result.data,{headers:{'Content-Type':'application/octet-stream','Content-Disposition':`attachment; filename="${file}"`,'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'}});
 }
 const result=await a.client.storage.from(bucket).list(prefix,{limit:100,sortBy:{column:'created_at',order:'desc'}});if(result.error)return json({error:'Arquivos indisponíveis.'},503);
 return json({items:(result.data||[]).filter(x=>memberFilePath(a.membership.organization_id,entry,x.name)).map(x=>({name:x.name,size:x.metadata?.size||0})),limit:100});
 }catch{return json({error:'Não foi possível processar o arquivo. Limite de 4 MB.'},400)}
}
export const GET=(r:Request)=>handle(r,false);
export const POST=(r:Request)=>handle(r,true);
