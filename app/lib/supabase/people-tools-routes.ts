// Pessoas · gestão: rotas de duplicados, histórico, novos convertidos, ações em lote e opções de filtro.
// O banco confere a igreja e quem pode ver ou editar cada pessoa; aqui só se valida a forma do pedido.
import {authorizeSupabaseChurch} from './church-access';
import {bulkInput,convertInput,mergeInput,peopleToolError} from '../people-tools';
import {uuidPattern} from '../private-files';

type RpcResult={data:unknown;error:{code?:string;message:string}|null};
type Rpc={rpc:(n:string,a:Record<string,unknown>)=>PromiseLike<RpcResult>};
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'private, no-store'}});
type Access=NonNullable<NonNullable<Awaited<ReturnType<typeof authorizeSupabaseChurch>>>['access']>;

async function withAccess(request:Request,scope:'people.read'|'people.write',run:(a:Access)=>Promise<Response>){
 const auth=await authorizeSupabaseChurch(request,scope);if(!auth||auth.response)return auth?.response||json({error:'Acesso indisponível.'},503);
 try{return await run(auth.access!)}catch(e){return json({error:e instanceof Error&&e.message.length<120?e.message:'Pedido inválido.'},400)}
}
async function call(a:Access,name:string,args:Record<string,unknown>){
 const r=await (a.client as unknown as Rpc).rpc(name,{p_org:a.membership.organization_id,...args});
 if(r.error){const e=peopleToolError(r.error.code);return json({error:e.error},e.status)}
 return json(r.data);
}
const unitOf=(a:Access,unit:string|null)=>{if(!unit||!uuidPattern.test(unit))throw Error('Escolha a igreja.');if(!a.membership.units.some(u=>u.id===unit))throw Error('Igreja sem acesso.');return unit};
const body=async(request:Request)=>{try{return await request.json()}catch{return null}};

export const duplicatesGET=(request:Request)=>withAccess(request,'people.read',async a=>call(a,'people_duplicates',{p_unit:unitOf(a,new URL(request.url).searchParams.get('unit')),p_action:'list',p_data:{}}));
export const duplicatesPOST=(request:Request)=>withAccess(request,'people.write',async a=>{const i=mergeInput(await body(request));return call(a,'people_duplicates',{p_unit:unitOf(a,i.unit),p_action:i.action,p_data:i.data})});
export const timelineGET=(request:Request)=>withAccess(request,'people.read',async a=>{
 const id=new URL(request.url).searchParams.get('id');if(!id||!uuidPattern.test(id))throw Error('Escolha a pessoa.');
 const r=await (a.client as unknown as Rpc).rpc('person_timeline',{p_org:a.membership.organization_id,p_person:id});
 if(r.error){const e=peopleToolError(r.error.code);return json({error:e.error},e.status)}
 return json({events:r.data});
});
export const convertsGET=(request:Request)=>withAccess(request,'people.read',async a=>{
 const q=new URL(request.url).searchParams,days=q.get('days')||'90';if(!['30','90','180','365'].includes(days))throw Error('Período inválido.');
 const r=await (a.client as unknown as Rpc).rpc('people_converts',{p_org:a.membership.organization_id,p_unit:unitOf(a,q.get('unit')),p_action:'list',p_data:{days:Number(days)}});
 if(r.error){const e=peopleToolError(r.error.code);return json({error:e.error},e.status)}
 return json({...(r.data as object),church:a.membership.organization_name});
});
export const convertsPOST=(request:Request)=>withAccess(request,'people.write',async a=>{const i=convertInput(await body(request));return call(a,'people_converts',{p_unit:unitOf(a,i.unit),p_action:'save',p_data:i.data})});
export const bulkPOST=(request:Request)=>withAccess(request,'people.write',async a=>{const i=bulkInput(await body(request));return call(a,'people_bulk',{p_unit:unitOf(a,i.unit),p_action:i.action,p_data:i.data})});

/** Opções dos filtros: células, redes e marcadores usados na igreja. */
export const optionsGET=(request:Request)=>withAccess(request,'people.read',async a=>{
 const unit=unitOf(a,new URL(request.url).searchParams.get('unit')),org=a.membership.organization_id;
 const [cells,networks,tags]=await Promise.all([
  a.client.from('church_cells').select('id,name').eq('organization_id',org).eq('unit_id',unit).eq('status','active').order('name').limit(500),
  a.client.from('church_cell_networks').select('id,name').eq('organization_id',org).eq('unit_id',unit).eq('status','active').order('name').limit(200),
  a.client.from('people').select('tags').eq('organization_id',org).eq('unit_id',unit).not('tags','eq','{}').limit(3000),
 ]);
 const set=new Set<string>();for(const row of (tags.data||[]) as {tags:string[]|null}[])for(const t of row.tags||[])if(t.trim())set.add(t.trim());
 return json({cells:cells.error?[]:cells.data,networks:networks.error?[]:networks.data,tags:[...set].sort((x,y)=>x.localeCompare(y,'pt-BR')).slice(0,200)});
});
