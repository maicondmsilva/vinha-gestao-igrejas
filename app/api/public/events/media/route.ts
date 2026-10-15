import { withLegacyContainment } from '../../../../lib/release-availability';
import { env } from 'cloudflare:workers';
import { NextResponse } from 'next/server';
async function legacyGET(request:Request){const id=new URL(request.url).searchParams.get('id'),media=await env.DB.prepare("SELECT m.object_key,m.content_type FROM event_media m JOIN events e ON e.id=m.event_id WHERE m.id=? AND e.status='published'").bind(id).first<{object_key:string;content_type:string}>();if(!media)return NextResponse.json({error:'Imagem não encontrada.'},{status:404});const object=await env.FILES.get(media.object_key);if(!object)return NextResponse.json({error:'Arquivo não encontrado.'},{status:404});return new Response(object.body,{headers:{'content-type':media.content_type,'cache-control':'public, max-age=86400'}})}

export const GET = withLegacyContainment(legacyGET);
