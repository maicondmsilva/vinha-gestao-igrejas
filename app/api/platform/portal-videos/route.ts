import {centralRoute,rows,rpc,requireValue,clean} from '../../../lib/supabase/operations';
import {portalEmbed,portalModules} from '../../../../shared/portal-content';
/** Central Vinha › Portal: link do vídeo (YouTube ou Vimeo) de cada módulo do Portal da Vinha. */
export const GET=centralRoute(async(_request,client)=>({modules:portalModules.map(m=>({id:m.id,title:m.title,status:m.status})),videos:await rows(client,'vinha_portal_videos')}));
export const PUT=centralRoute(async(request,client)=>{
 requireValue(request.headers.get('origin')===new URL(request.url).origin,'Origem inválida.',403);
 const d=await request.json<{module?:string;url?:string}>(),module=clean(d.module,30),url=clean(d.url,300);
 requireValue(portalModules.some(m=>m.id===module),'Módulo inválido.');
 requireValue(!url||portalEmbed(url),'Use um link do YouTube ou do Vimeo.');
 await rpc(client,'save_portal_video',{p_module:module,p_url:url});
 return{ok:true,videos:await rows(client,'vinha_portal_videos')};
});
